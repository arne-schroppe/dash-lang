module Language.Spot.Normalization.Normalization (
  normalize
) where

import           Control.Monad.State hiding (state)
import           Language.Spot.IR.Ast
import           Language.Spot.IR.Data
import           Language.Spot.IR.Nst
import           Language.Spot.Normalization.NormalizationState
import           Language.Spot.Normalization.Recursion


{-

Normalization
~~~~~~~~~~~~~

This module normalizes the abstract syntax tree (Ast) generated by the parser into
a normalized form (Nst) that is easier for the code generator to compile. Mainly,
the normalized form assigns all intermediate results to a name (let-binding). For
example, the code

set-value (at list 2) (3 * 6)

would be normalized to something like

let temp1 = 2
let temp2 = at [list, temp1]
let temp3 = 3 * 6
set-value [temp2, temp3]


Types of variables
~~~~~~~~~~~~~~~~~~

The actual form doesn't generate string identifiers like "temp1", though. Instead
it uses the type NstVar. In this type, a LocalVar is one of the temporary generated
during normalization or an explicit local let-binding. A FunParam is a formal parameter
in a lambda.

The more interesting one's are DynamicFreeVar and ConstantFreeVar. A ConstantFreeVar is a
free variable in a lambda that is a constant known value in the surrounding scope. Lambdas
that are not closures (i.e. don't have any free variables) count as constant values too.
A ConstantFreeVar is resolved directly (by loading the function address or the constant)
and doesn't need any further support.

A DynamicFreeVar is a free variable that is not a compile time constant. These are later
added to a lambda as additional parameters. This module traces dynamic free variables and
mentions them explicitly for every `Nst.Lambda`.


Recursion
~~~~~~~~~

This module works in two passes. The first pass is the normalization described earlier,
the second pass resolves recursion. The resulting normalized code will not contain any
RecursiveVar


-}


type Cont = NstAtomicExpr -> NormState NstExpr
type VCont = NstVar -> NormState NstExpr

normalize :: Expr -> (NstExpr, ConstTable, SymbolNameList)
normalize expr =
  let (result, finalState) = runState (normalizeInContext expr) emptyNormEnv in
  let result' = resolveRecursion result in
  (result', constTable finalState, getSymbolNames finalState)

normalizeInContext :: Expr -> NormState NstExpr
normalizeInContext expr = do
  enterContext []
  nExpr <- normalizeExpr expr
  leaveContext
  return nExpr


normalizeExpr :: Expr -> NormState NstExpr
normalizeExpr expr = case expr of
  LocalBinding (Binding name boundExpr) restExpr ->
    nameExpr boundExpr name $ \ var -> do
      -- TODO use isDynamic here
      addBinding name (var, False)
      rest <- normalizeExpr restExpr
      return $ rest
  _ -> do
    atomizeExpr expr "" $ return . NAtom


atomizeExpr :: Expr -> String -> Cont -> NormState NstExpr
atomizeExpr expr name k = case expr of
  FunCall funExpr args ->
          normalizeFunCall funExpr args k
  LitNumber n ->
          normalizeNumber n k
  LitSymbol sname args ->
          normalizeSymbol sname args k
  Var vname ->
          normalizeVar vname k
  Match matchedExpr patterns ->
          normalizeMatch matchedExpr patterns k
  Lambda params bodyExpr ->
          normalizeLambda params bodyExpr name k
  LocalBinding (Binding bname boundExpr) restExpr -> -- inner local binding ! (i.e. let a = let b = 2 in 1 + b)
          atomizeExpr boundExpr bname $ \ aExpr -> do
            var <- newTempVar bname
            addBinding bname (var, False)
            atomizeExpr restExpr "" $ \ normBoundExpr -> do
              rest <- k normBoundExpr
              return $ NLet var aExpr rest
  x -> error $ "Unable to normalize " ++ (show x)


normalizeNumber :: Int -> Cont -> NormState NstExpr
normalizeNumber n k = k (NNumber n)


normalizeSymbol :: String -> [Expr] -> Cont -> NormState NstExpr
normalizeSymbol sname [] k = do
  symId <- addSymbolName sname
  k (NPlainSymbol symId)

normalizeSymbol sid args k = do
  encConst <- encodeConstant $ LitSymbol sid args
  cAddr <- addConstant encConst
  k (NCompoundSymbol False cAddr)

-- There are three cases:
--   - static symbols, which are completely in the sym table
--   - dynamic symbols, which have some dynamic elements. A template for these can be
--     generated in the sym table and then be copied and modified
--   - unknown dynamism. This happens when symbols include free vars. We need to
--     resolve at a later point whether the closed over var is static or dynamic
--     (or do we?)
{-
  normalizeExprList args $ \ normArgs ->
          k $ NFunCall $ funVar : normArgs
-}


-- This is only direct usage of a var (as a "return value")
normalizeVar :: String -> Cont -> NormState NstExpr
normalizeVar name k = do
  var <- lookupName name
  k $ NVar var


normalizeLambda :: [String] -> Expr -> String -> Cont -> NormState NstExpr
normalizeLambda params bodyExpr name k = do
  enterContext params
  when (not $ null name) $ addBinding name (NRecursiveVar name, False) -- TODO we don't know whether this var is dynamic or not!
  normalizedBody <- normalizeExpr bodyExpr
  freeVars <- freeVariables
  leaveContext
  pullUpFreeVars freeVars
  k $ NLambda freeVars params normalizedBody


normalizeFunCall :: Expr -> [Expr] -> Cont -> NormState NstExpr
normalizeFunCall funExpr args k = case (funExpr, args) of
  (Var "add", [a, b]) -> normalizeMathPrimOp NPrimOpAdd a b k
  (Var "sub", [a, b]) -> normalizeMathPrimOp NPrimOpSub a b k
  _ -> do nameExpr funExpr "" $ \ funVar ->
            normalizeExprList args $ \ normArgs ->
              k $ NFunCall funVar normArgs
  where
    normalizeMathPrimOp :: (NstVar -> NstVar -> NstPrimOp) -> Expr -> Expr -> Cont -> NormState NstExpr
    normalizeMathPrimOp mathPrimOp a b kk = do
      normalizeExprList [a, b] $ \ [aVar, bVar] ->
          kk $ NPrimOp $ mathPrimOp aVar bVar


normalizeMatch :: Expr -> [(Pattern, Expr)] -> Cont -> NormState NstExpr
normalizeMatch matchedExpr patternsAndExpressions k = do
  matchedVarsAndEncodedPatterns <- forM (map fst patternsAndExpressions) $ encodeMatchPattern 0
  let matchedVars = map fst matchedVarsAndEncodedPatterns
  patternAddr <- addConstant $ CMatchData $ map snd matchedVarsAndEncodedPatterns
  let exprs = map snd patternsAndExpressions
  -- we wrap each match branch in a lambda. This way we can handle them easier in the codegenerator
  let maxMatchVars = maximum $ map length matchedVars
  let lambdaizedExprs = map (\ (params, expr) -> Lambda params expr) $ zip matchedVars exprs
  nameExpr matchedExpr "" $ \ subjVar ->
          normalizeExprList lambdaizedExprs $ \ branchVars -> do
                  let branches = zip matchedVars branchVars
                  k $ NMatch maxMatchVars subjVar patternAddr branches





----- Normalization helper functions -----

-- TODO shouldn't this be called something like nameExprList ?

-- Free variables in a used lambda which can't be resolved in our context need to become
-- free variables in our context
pullUpFreeVars :: [String] -> NormState ()
pullUpFreeVars freeVars = do
  _ <- forM (reverse freeVars) $ \ name -> do
          hasB <- hasBinding name
          when (not hasB) $ addDynamicVar name
  return ()


normalizeExprList :: [Expr] -> ([NstVar] -> NormState NstExpr) -> NormState NstExpr
normalizeExprList exprList k =
  normalizeExprList' exprList [] k
  where
    normalizeExprList' [] acc k' = do
      expr <- k' $ reverse acc
      return expr
    normalizeExprList' expLs acc k' = do
      let hd = head expLs
      nameExpr hd "" $ \ var -> do
        restExpr <- normalizeExprList' (tail expLs) (var : acc) k'
        return restExpr


-- TODO rename this function to something more appropriate
nameExpr :: Expr -> String -> VCont -> NormState NstExpr
nameExpr expr originalName k = case expr of
  -- Some variable can be used directly and don't need to be let-bound
  Var name -> do
    var <- lookupName name
    case var of
      -- Constant free vars are let-bound
      NConstantFreeVar _ -> letBind expr "" k
      -- Recursive vars are also let-bound. Not strictly necessary, but easier later on  (TODO loosen this restriction)
      NRecursiveVar _ -> letBind expr "" k
      -- All other vars are used directly (because they will be in a register later on)
      v -> do
            bodyExpr <- k v
            return bodyExpr
  -- Everything that is not a Var needs to be let-bound
  _ -> letBind expr originalName k
  where
    letBind :: Expr -> String -> VCont -> NormState NstExpr
    letBind e n k' = do
      atomizeExpr e n $ \ aExpr -> do
        var <- newTempVar n
        restExpr <- k' var
        return $ NLet var aExpr restExpr

{-
isAtomDynamic expr = case expr of
  NLambda (h:_) _ _ -> True
  NCompoundSymbol True _ -> True
  _ -> False
-}




----- Recursion

