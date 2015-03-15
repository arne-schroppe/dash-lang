module Language.Spot.CodeGen.CodeGen (
  compile
) where

import Language.Spot.CodeGen.CodeGenState
import Language.Spot.IR.Ast
import Language.Spot.IR.Opcode
import Language.Spot.VM.Bits

import Control.Monad.State
import Control.Applicative
import Data.Word
import Data.Maybe
import Data.Monoid
import Control.Exception.Base




compile :: Expr -> ([[Opcode]], ConstTable, SymbolNameList)
compile ast = (getOpcodes result, getCTable result, getSymNames result) --todo reverse most of this
  where result = execState (addStartFunction ast) emptyCode

addStartFunction e = do
  beginFunction
  code <- compileExpression e
  setFunctionCode 0 (code ++ [Op_ret])
  endFunction



compileExpression e = case e of
  LitNumber n       -> compileLitNumber n
  LitSymbol s vals  -> compileLitSymbol s vals
  FunCall name args -> compileFunCall name args
  LocalBinding (Binding name expr) body -> compileLocalBinding name expr body
  Var a             -> compileVar a
  Match e pats      -> compileMatch e pats
  a -> error $ "Can't compile: " ++ show a

compileLitNumber n = do
  r <- resultReg
  return [Op_load_i r (fromIntegral n)]

compileLitSymbol s []   = do
  newId <- addSymbolName s
  r <- resultReg
  return [Op_load_s r newId]
compileLitSymbol s args = do
  symId <- addSymbolName s
  r <- resultReg
  let symHeader = encDataSymbolHeader symId (fromIntegral $ length args)
  let symEntry = symHeader : (map encodeAstValue args)
  newAddr <- addConstants symEntry
  return [Op_load_sd r newAddr]

compileFunCall (Var "add") (op1:op2:[]) = -- do we really need opcodes for math stuff? How about built-in functions?
  compileMathFunc Op_add op1 op2
compileFunCall (Var "sub") (op1:op2:[]) =
  compileMathFunc Op_sub op1 op2
compileFunCall (Var funName) args = do
  resReg <- resultReg
  fr <- regContainingVar funName -- TODO it would be more efficient if we would simply load_f in here
  (code, nfr) <- ensureContinuousRegisters fr
  argRegs <- replicateM (length args) reserveReg
  let regsAndArgs = zip argRegs args
  argCode <- forM regsAndArgs (\(aReg, arg) -> do
    evalArgument arg aReg)
  return $ code ++
           (concat argCode) ++
           [ Op_call resReg nfr (fromIntegral $ length args) ]
compileFunCall _ _ = error "Unknown function"

-- The registers for args must come immediately after the one for the
-- function address. Here we're making sure that that holds true.
ensureContinuousRegisters funcReg = do
  nextRegister <- peekReg
  if (nextRegister /= (funcReg + 1)) then do
    newFr <- reserveReg
    let code = [ Op_move newFr funcReg ]
    return (code, newFr)
  else
    return ([], funcReg)

compileLocalBinding name (FunDef args expr) body = do
  r <- reserveReg
  funAddr <- compileFunction args expr
  addVar name r
  let code = [Op_load_f r funAddr]
  bodyCode <- compileExpression body
  return $ code ++ bodyCode
compileLocalBinding name expr body = do
  r <- reserveReg
  pushResultReg r
  exprCode <- compileExpression expr
  popResultReg
  addVar name r
  bodyCode <- compileExpression body
  return $ exprCode ++
           bodyCode

compileFunction args expr = do
  funAddr <- beginFunction
  forM_ args (\arg -> do
    r <- reserveReg
    addVar arg r)
  code <- compileExpression expr
  setFunctionCode funAddr (code ++ [Op_ret])
  endFunction
  return funAddr

compileVar a = do
  r <- resultReg
  r1 <- regContainingVar a
  return [ Op_move r r1 ]

compileMathFunc mf op1 op2 = do
  r <- resultReg
  argRegs <- replicateM 2 reserveReg
  let regsAndArgs = zip argRegs [op1, op2]
  varCode <- forM regsAndArgs (\(aReg, arg) -> do
    evalArgument arg aReg)
  return $ (concat varCode) ++
           [ mf r (argRegs !! 0) (argRegs !! 1) ]


compileMatch expr patsAndExprs = do
  let numPats = length patsAndExprs
  matchDataAddr <- storeMatchPattern $ map fst patsAndExprs
  matchStartCode <- createMatchCall expr matchDataAddr
  exprCodes <- forM (map snd patsAndExprs) compileExpression

  let (exprJmpTargets, contJmpTargets) = unzip $ map (calcJumpTargets numPats exprCodes) [0..(numPats - 1)]
  let jmpTableCodes = map (singleOp . Op_jmp) exprJmpTargets
  let bodyCodes = map (uncurry (++)) $ zip exprCodes $ map (singleOp . Op_jmp) contJmpTargets

  return $ matchStartCode ++
           (concat jmpTableCodes) ++
           (concat bodyCodes)
  where
    storeMatchPattern ps = do
        encodedPatterns <- mapM encodePattern ps
        let encoded = encMatchHeader (fromIntegral $ length ps) : encodedPatterns
        addConstants encoded

    createMatchCall expr matchDataAddr = do
      subjReg <- reserveReg
      argCode <- evalArgument expr subjReg
      patReg <- reserveReg
      return $ argCode ++
               [ Op_load_i patReg matchDataAddr
               , Op_match subjReg patReg 0 ]

    calcJumpTargets numPats exprCodes idx =
      let (pre, post) = splitAt idx exprCodes in
      let jmpToFirstExpr = (numPats - idx - 1) in
      let jmpToActualExpr = foldl (\acc ls -> acc + 1 + length ls) 0 pre in
      let exprJmpTarget = fromIntegral $ jmpToFirstExpr + jmpToActualExpr in

      -- contJmpTarget: relative address of code after the match body
      let lenRemainingResultExprs = foldl ( flip $ (+) . length) 0 (tail post) in
      let lenExtraJmps = (numPats - idx) - 1 in -- for every remaining result expr we need to add one jump expr
      let contJmpTarget = fromIntegral $ lenRemainingResultExprs + lenExtraJmps in

      (exprJmpTarget, contJmpTarget)

    singleOp = (:[])



-- for match vars:
-- keep track of vars for each expression
-- reserve maximum var number of registers
-- when evaluating expr, do so in a local context with those registers

encodePattern pat =
  case pat of
    PatNumber n -> return (encNumber $ fromIntegral n)
    PatSymbol s [] -> do sid <- addSymbolName s
                         return $ encSymbol sid
    PatVar n -> return $ encMatchVar 0
      -- reserve register, bind name to register, encode var
    x -> error $ "Can't encode match pattern: " ++ (show x)

evalArgument (Var n) targetReg = do
  vr <- regContainingVar n -- This is also wasteful. In most cases, we'll just reserve two registers per var
  if (vr /= targetReg) then do return [ Op_move targetReg vr ]
  else return []
evalArgument arg r   = do
  pushResultReg r
  code <- compileExpression arg
  popResultReg
  return code

encodeAstValue (LitNumber n) = encNumber $ fromIntegral n
encodeAstValue _ = error "can't encode symbol"






