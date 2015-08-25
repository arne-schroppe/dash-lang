module Language.Dash.Normalization.Normalization (
  normalize
) where

import           Control.Monad
import           Control.Monad.Except                           (runExceptT,
                                                                 throwError)
import           Control.Monad.Identity                         (runIdentity)
import           Control.Monad.State.Strict
import           Language.Dash.BuiltIn.BuiltInDefinitions       (builtInFunctions)
import           Language.Dash.Error.Error                      (CompilationError (..))
import           Language.Dash.IR.Ast
import           Language.Dash.IR.Data
import           Language.Dash.IR.Nst
import           Language.Dash.Normalization.NormalizationState
import           Language.Dash.Normalization.Recursion


{-

Normalization
~~~~~~~~~~~~~

This module normalizes the abstract syntax tree (Ast) generated by the parser into
a normalized form (Nst) that is easier for the code generator to compile. Mainly,
the normalized form assigns all intermediate results to a name (let-binding). For
example, the code

    read-position csv (row-length * 5 + 7)

would be normalized to something like

    let temp1 = 5
    let temp2 = (*) [row-length, temp1]
    let temp3 = 7
    let temp4 = (+) [temp2, temp3]
    read-position [csv, temp4]


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
adds them explicitly to every `Nst.Lambda`.


Recursion
~~~~~~~~~

This module works in two passes. The first pass is the normalization described earlier,
the second pass resolves recursion. The resulting normalized code will not contain any
`Nst.RecursiveVar`

-}

-- TODO add writer with breadcrumbs for debugging
-- TODO add another writer for warnings (globally)

type Cont = NstAtomicExpr -> Norm NstExpr
type VCont = NstVar -> Norm NstExpr


normalize :: Expr -> Either CompilationError (NstExpr, ConstTable, SymbolNameList)
normalize expr = do
  (result, finalState) <- runIdentity $ runExceptT $ runStateT (normalizeInContext expr) emptyNormState
  result' <- resolveRecursion result
  return (result', constTable finalState, getSymbolNames finalState)


normalizeInContext :: Expr -> Norm NstExpr
normalizeInContext expr = do
  enterContext []
  addBIFPlaceholders
  nExpr <- normalizeExpr expr
  leaveContext
  return nExpr

addBIFPlaceholders :: Norm ()
addBIFPlaceholders =
  void $ forM builtInFunctions $ \ (name, bifArity, _) ->
                 addBIFPlaceholder name bifArity

addBIFPlaceholder :: String -> Int -> Norm ()
addBIFPlaceholder name ar = do
  let var = NVar name NConstant
  addBinding name (var, False)
  addArity name 0 ar

normalizeExpr :: Expr -> Norm NstExpr
normalizeExpr expr = case expr of
  LocalBinding (Binding name (Var v)) restExpr -> do
      addAlias name v
      normalizeExpr restExpr
  LocalBinding (Binding name boundExpr) restExpr ->
    nameExpr boundExpr name $ \ _ -> normalizeExpr restExpr
  _ ->
    atomizeExpr expr "" $ return . NAtom


atomizeExpr :: Expr -> String -> Cont -> Norm NstExpr
atomizeExpr expr name k = case expr of
  FunAp funExpr args ->
      normalizeFunAp funExpr args k
  LitNumber n ->
      normalizeNumber n k
  LitSymbol sname args ->
      normalizeSymbol sname args k
  LitString s ->
      normalizeString s k
  Var vname ->
      normalizeVar vname k
  Match matchedExpr patterns ->
      normalizeMatch matchedExpr patterns k
  Lambda params bodyExpr ->
      normalizeLambda params bodyExpr name k
  MatchBranch matchedVars bodyExpr ->
      normalizeMatchBranch matchedVars bodyExpr k
  Module bindings ->
      let bs = map (\ (Binding n e) -> (n, e)) bindings in
      normalizeModule bs k
  Qualified ident e ->
      normalizeModuleLookup ident e k
  LocalBinding (Binding bname boundExpr) restExpr ->
      normalizeInnerLocalBinding bname boundExpr restExpr k


-- This case is only for inner local bindings, i.e. let a = let b = 2 in 1 + b
-- (So in that example "let b = ..." is the inner local binding)
normalizeInnerLocalBinding :: String -> Expr -> Expr -> Cont -> Norm NstExpr
normalizeInnerLocalBinding bname boundExpr restExpr k =
    atomizeExpr boundExpr bname $ \ aExpr -> do
      let var = NVar bname NLocalVar
      addBinding bname (var, False)
      atomizeExpr restExpr "" $ \ normBoundExpr -> do
        rest <- k normBoundExpr
        return $ NLet var aExpr rest

normalizeModule :: [(Name, Expr)] -> Cont -> Norm NstExpr
normalizeModule bindings k = do
  let names = map fst bindings
  nExprs <- atomizeList bindings
  nSyms <- mapM addSymbolName names
  let fields = zip3 nSyms names nExprs
  let nmodule = NModule fields
  k nmodule

normalizeModuleLookup :: Name -> Expr -> Cont -> Norm NstExpr
normalizeModuleLookup modName (Var v) k = do
  modVar <- lookupName modName
  nameExpr (LitSymbol v []) "" $ \ symVar ->
    k $ NModuleLookup modVar symVar
normalizeModuleLookup _ qExpr _ = throwError $ InternalCompilerError $ "Unable to do name lookup with " ++ show qExpr


atomizeList :: [(Name, Expr)] -> Norm [NstAtomicExpr]
atomizeList [] =
  return []
atomizeList exprs = do
  let (name, expr) = head exprs
  (NAtom nAtomExpr) <- atomizeExpr expr name $ return . NAtom
  rest <- atomizeList (tail exprs)
  return $ nAtomExpr : rest

normalizeNumber :: Int -> Cont -> Norm NstExpr
normalizeNumber n k = k (NNumber n)

normalizeString :: String -> Cont -> Norm NstExpr
normalizeString s k = do
  encString <- encodeConstantString s
  strAddr <- addConstant encString
  k (NString strAddr)

normalizeSymbol :: String -> [Expr] -> Cont -> Norm NstExpr
normalizeSymbol sname [] k = do
  symId <- addSymbolName sname
  k (NPlainSymbol symId)
normalizeSymbol sname args k =
  if isDynamicLiteral $ LitSymbol sname args then
    let indicesAndDynamicValues = indexedDynamicSymbolFields args in
    let indices = map fst indicesAndDynamicValues in
    let dynamicVars = map snd indicesAndDynamicValues in
    nameExprList dynamicVars $ \ freeVars -> do
      -- Get a list of all dynamic values and their positions. Then
      -- let-bind the dynamic values. At the dynamic positions inside the
      -- symbol just set 0. Codegen will then take that const symbol, copy
      -- it to the heap and set the let-bound values at their respective
      -- positions.
      let zeroedFields = setZeroesAtIndices args indices
      encConst <- encodeConstantCompoundSymbol sname zeroedFields
      cAddr <- addConstant encConst
      let indicesAndVars = zip indices freeVars
      k $ NCompoundSymbol indicesAndVars cAddr
  else do
    encConst <- encodeConstantCompoundSymbol sname args
    cAddr <- addConstant encConst
    k (NCompoundSymbol [] cAddr)

-- Only dynamic values in the list and their index
indexedDynamicSymbolFields :: [Expr] -> [(Int, Expr)]
indexedDynamicSymbolFields fields =
  filter (isDynamicLiteral.snd) $ zipWithIndex fields

setZeroesAtIndices :: [Expr] -> [Int] -> [Expr]
setZeroesAtIndices fields indices =
  map (\ (index, e) ->
    if index `elem` indices then
      LitNumber 0
    else
      e) $
    zipWithIndex fields


isDynamicLiteral :: Expr -> Bool
isDynamicLiteral v =
  case v of
    LitNumber _ -> False
    LitSymbol _ [] -> False
    LitSymbol _ args -> any isDynamicLiteral args
    _ -> True



normalizeVar :: String -> Cont -> Norm NstExpr
normalizeVar name k = do
  var <- lookupName name
  k $ NVarExpr var


normalizeLambda :: [String] -> Expr -> String -> Cont -> Norm NstExpr
normalizeLambda params bodyExpr name k = do
  enterContext params
  -- TODO we don't know whether this var is dynamic or not!
  addBinding name (NVar name NRecursiveVar, False)
  -- TODO add arity for recursive var?
  normalizedBody <- normalizeExpr bodyExpr
  freeVars <- freeVariables
  leaveContext
  pullUpFreeVars freeVars
  addArity name (length freeVars) (length params)
  k $ NLambda freeVars params normalizedBody


normalizeMatchBranch :: [String] -> Expr -> Cont -> Norm NstExpr
normalizeMatchBranch matchedVars bodyExpr k = do
  enterContext matchedVars
  -- TODO add arity for recursive var?
  normalizedBody <- normalizeExpr bodyExpr
  freeVars <- freeVariables
  leaveContext
  pullUpFreeVars freeVars
  k $ NMatchBranch freeVars matchedVars normalizedBody


-- TODO throw an error if the thing being called is obviously not callable
-- TODO it gets a bit confusing in which cases we expect a closure and where we expect
-- a simple function
normalizeFunAp :: Expr -> [Expr] -> Cont -> Norm NstExpr
normalizeFunAp funExpr args k =
  case (funExpr, args) of
    (Var "+", [a, b])  -> normalizeBinaryPrimOp NPrimOpAdd a b
    (Var "-", [a, b])  -> normalizeBinaryPrimOp NPrimOpSub a b
    (Var "*", [a, b])  -> normalizeBinaryPrimOp NPrimOpMul a b
    (Var "/", [a, b])  -> normalizeBinaryPrimOp NPrimOpDiv a b
    (Var "<", [a, b])  -> normalizeBinaryPrimOp NPrimOpLessThan a b
    (Var ">", [a, b])  -> normalizeBinaryPrimOp NPrimOpGreaterThan a b
    (Var "||", [a, b]) -> normalizeBinaryPrimOp NPrimOpOr a b
    (Var "&&", [a, b]) -> normalizeBinaryPrimOp NPrimOpAnd a b
    (Var "!", [a])   -> normalizeUnaryPrimOp NPrimOpNot a
    (Var "==", [a, b]) -> normalizeBinaryPrimOp NPrimOpEq a b
    -- TODO create a bif that calls the primap internally

    _ -> nameExpr funExpr "" $ \ funVar -> do
      maybeAr <- arity funVar
      case maybeAr of
        Nothing -> applyUnknownFunction funVar
        Just (numFree, ar) -> applyKnownFunction funVar numFree ar
  where
    normalizeUnaryPrimOp :: (NstVar -> NstPrimOp)
                          -> Expr
                          -> Norm NstExpr
    normalizeUnaryPrimOp primOp a =
      nameExprList [a] $ \ [aVar] ->
          k $ NPrimOp $ primOp aVar

    normalizeBinaryPrimOp :: (NstVar -> NstVar -> NstPrimOp)
                          -> Expr
                          -> Expr
                          -> Norm NstExpr
    normalizeBinaryPrimOp primOp a b =
      nameExprList [a, b] $ \ [aVar, bVar] ->
          k $ NPrimOp $ primOp aVar bVar


    applyUnknownFunction :: NstVar -> Norm NstExpr
    applyUnknownFunction funVar =
      nameExprList args $ \ normArgs ->
          k $ NFunAp funVar normArgs

    applyKnownFunction :: NstVar -> Int -> Int -> Norm NstExpr
    applyKnownFunction funVar numFreeVars funArity =
      let numArgs = length args in
      -- saturated call
      if numArgs == funArity then
        nameExprList args $ \ normArgs ->
            k $ NFunAp funVar normArgs
      -- under-saturated call
      else if numArgs < funArity then
        -- We already know at this point, that this *must* be a non-closure
        if numFreeVars > 0
          then throwError $ InternalCompilerError
                  "Trying to do static partial application of closure"
        else nameExprList args $ \ normArgs ->
               k $ NPartAp funVar normArgs
      -- over-saturated call
      else do -- numArgs > funArity
        let (knownFunArgs, remainingArgs) = splitAt funArity args
        nameExprList knownFunArgs $ \ normKnownFunArgs -> do
          knownFunResult <- newTempVar
          let apKnownFun = NFunAp funVar normKnownFunArgs
          nameExprList remainingArgs $ \ normRemArgs -> do
            -- The previous function application should have resulted in a new function
            -- , which we're applying here
            rest <- k $ NFunAp knownFunResult normRemArgs
            return $ NLet knownFunResult apKnownFun rest


normalizeMatch :: Expr -> [(Pattern, Expr)] -> Cont -> Norm NstExpr
normalizeMatch matchedExpr patternsAndExpressions k = do
  matchedVarsAndEncodedPatterns <- forM (map fst patternsAndExpressions) $
                                        encodeMatchPattern 0
  let matchedVars = map fst matchedVarsAndEncodedPatterns
  patternAddr <- addConstant $ CMatchData $ map snd matchedVarsAndEncodedPatterns
  let exprs = map snd patternsAndExpressions
  let maxMatchVars = maximum $ map length matchedVars
  -- we wrap each match branch in a lambda. This way we can handle them easier in the
  -- code generator. But the lambda has a different constructor, called MatchBranch,
  -- which helps us in optimizing the compiled code (free variables in matchBranches are
  -- not pushed as a closure on the heap, for example).
  nameExpr matchedExpr "" $ \ subjVar ->
    let matchBranches = zipWith MatchBranch matchedVars exprs in
    nameExprList matchBranches $ \ branchVars -> do
      -- for now we're only inserting empty lists instead of free vars. The
      -- recursion module will insert the actual free vars of each match
      -- branch, because only that module has full knowledge of them
      let freeVars = replicate (length branchVars) []
      let branches = zip3 freeVars matchedVars branchVars
      k $ NMatch maxMatchVars subjVar patternAddr branches


----- Normalization helper functions

-- Free variables in a closure used by us which can't be resolved in our context need to
-- become free variables in our context
pullUpFreeVars :: [String] -> Norm ()
pullUpFreeVars freeVars = do
  _ <- forM (reverse freeVars) $ \ name -> do
          hasB <- hasBinding name
          unless hasB $ addDynamicVar name
  return ()


nameExprList :: [Expr] -> ([NstVar] -> Norm NstExpr) -> Norm NstExpr
nameExprList exprList =
  nameExprList' exprList []
  where
    nameExprList' [] acc k' =
      k' $ reverse acc
    nameExprList' expLs acc k' =
      nameExpr (head expLs) "" $ \ var ->
        nameExprList' (tail expLs) (var : acc) k'

-- Used for the local name of a constant we're let-binding in the
-- current scope (So that subsequent uses of that constant can reuse
-- that local var and don't have to rebind that constant)
localConstPrefix :: String
localConstPrefix = "$locconst:"

nameExpr :: Expr -> String -> VCont -> Norm NstExpr
nameExpr expr originalName k = case expr of
  -- Some variable can be used directly and don't need to be let-bound
  Var name -> do
    var <- lookupName name
    case var of
      -- Constant free vars are let-bound
      NVar constName NConstant -> do
        let localConstName = localConstPrefix ++ constName
        -- do we already have a local binding for this constant?
        hasLocalName <- hasBinding localConstName
        if hasLocalName
            then k (NVar localConstName NLocalVar)
            else letBind expr localConstName k
      -- Recursive vars are also let-bound. Not strictly necessary, but easier later on  (TODO loosen this restriction)
      NVar _ NRecursiveVar -> letBind expr "" k
      -- All other vars are used directly (because they will be in a register later on)
      v -> k v
  -- Everything that is not a Var needs to be let-bound
  _ -> letBind expr originalName k
  where
    letBind :: Expr -> String -> (NstVar -> Norm NstExpr) -> Norm NstExpr
    letBind expr' name k' =
      atomizeExpr expr' name $ \ aExpr -> do
        var <- if null name then newTempVar else return $ NVar name NLocalVar
        addBinding name (var, isDynamic aExpr)
        restExpr <- k' var
        return $ NLet var aExpr restExpr


isDynamic :: NstAtomicExpr -> Bool
isDynamic aExpr =
  case aExpr of
    NNumber _ -> False
    NPlainSymbol _ -> False
    NString _ -> False
    NLambda [] _ _ -> False
    _ -> True

zipWithIndex :: [a] -> [(Int, a)]
zipWithIndex values = zip [0..(length values)] values


-- Encoding

encodeConstantCompoundSymbol :: Name -> [Expr] -> Norm Constant
encodeConstantCompoundSymbol symName symArgs = do
  symId <- addSymbolName symName
  encodedArgs <- mapM encodeConstantLiteral symArgs
  return $ CCompoundSymbol symId encodedArgs

encodeConstantString :: String -> Norm Constant
encodeConstantString str =
  return $ CString str

encodeConstantLiteral :: Expr -> Norm Constant
encodeConstantLiteral v =
  case v of
    LitNumber n ->
        return $ CNumber n
    LitSymbol s [] -> do
        sid <- addSymbolName s
        return $ CPlainSymbol sid
    LitSymbol s args ->
        encodeConstantCompoundSymbol s args
    -- TODO allow functions here?
    _ ->
        throwError $ CodeError "Expected a literal"

encodeMatchPattern :: Int -> Pattern -> Norm ([String], Constant)
encodeMatchPattern nextMatchVar pat =
  case pat of
    PatNumber n ->
        return ([], CNumber n)
    PatSymbol s [] -> do
        sid <- addSymbolName s
        return ([], CPlainSymbol sid)
    PatSymbol s params -> do
        symId <- addSymbolName s
        (vars, pats) <- encodePatternCompoundSymbolArgs nextMatchVar params
        return (vars, CCompoundSymbol symId pats)
    PatVar n ->
        return ([n], CMatchVar nextMatchVar)
    PatWildcard ->
        return (["_"], CMatchVar nextMatchVar) -- TODO be a bit more sophisticated here
                                               -- and don't encode this as a var that is
                                               -- passed to the match branch


-- TODO use inner state ?
encodePatternCompoundSymbolArgs :: Int -> [Pattern] -> Norm ([String], [Constant])
encodePatternCompoundSymbolArgs nextMatchVar args = do
  (_, vars, entries) <- foldM (\(nextMV, accVars, pats) p -> do
    (vars, encoded) <- encodeMatchPattern nextMV p
    return (nextMV + fromIntegral (length vars), accVars ++ vars, pats ++ [encoded])
    ) (nextMatchVar, [], []) args  -- TODO get that O(n*m) out and make it more clear
                                   -- what this does
  return (vars, entries)



