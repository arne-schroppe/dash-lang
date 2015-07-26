module Language.Dash.Asm.Assembler (
  assemble
, assembleWithEncodedConstTable
) where


import           Data.Bits
import qualified Data.Sequence                   as Seq
import           Language.Dash.Asm.DataAssembler
import           Language.Dash.IR.Data
import           Language.Dash.IR.Tac
import           Language.Dash.VM.Types


{-

Assembler
~~~~~~~~~

The assembler takes lists of three address codes and generates the actual byte code for
the virtual machine. It also encodes all static objects used at runtime (the const table).
The latter is done by the DataAssembler.

The code generator stores each function as a list, so the input type for the assembler
is [[tac]]. Function addresses in the input code are indices of the outer list. They are
turned into real addresses by the assembler.

-}



assemble :: [[Tac]]
         -> ConstTable
         -> SymbolNameList
         -> ([VMWord], [VMWord], SymbolNameList)
assemble funcs ctable symnames =
  let (consts, addrConvert) = encodeConstTable ctable in
  assembleWithEncodedConstTable funcs consts addrConvert symnames


assembleWithEncodedConstTable :: [[Tac]]
                              -> [VMWord]
                              -> (ConstAddr
                              -> VMWord)
                              -> SymbolNameList
                              -> ([VMWord], [VMWord], SymbolNameList)
assembleWithEncodedConstTable funcs encCTable constAddrConverter symnames =
  (map assembleOpcode instructions, encCTable, symnames)
  where
    assembleOpcode = assembleTac funcAddrs constAddrConverter
    instructions = fst combined
    funcAddrs = snd combined
    combined = combineFunctions funcs


-- Converts the nested list of functions into a flat list, and additionally provides
-- a map from indices in the nested list to the index in the flat list (that map is
-- just a sequence with the same length as the nested list). The map helps us to find
-- function references in the Tac code in our generated binary code.
combineFunctions :: [[Tac]] -> ([Tac], Seq.Seq VMWord)
combineFunctions =
  foldl calcFuncAddr ([], Seq.empty)
  where
    calcFuncAddr acc funcInstrs =
      let allInstrs = fst acc in
      let funcAddrs = snd acc in
      ( allInstrs ++ funcInstrs, funcAddrs Seq.|> fromIntegral (length allInstrs) )


assembleTac :: Seq.Seq VMWord -> (ConstAddr -> VMWord) -> Tac -> VMWord
assembleTac funcAddrs addrConv opc =
  let r = regToInt in
  let i = fromIntegral in
  let sym = fromIntegral . symIdToInt in
  let caddr a = fromIntegral (addrConv a) in
  let faddr a = fromIntegral $ funcAddrs `Seq.index` funcAddrToInt a in
  case opc of
    Tac_ret r0              -> instructionRI   0 (r r0) 0
    Tac_load_i r0 n         -> instructionRI   1 (r r0) n
    Tac_load_addr r0 a      -> instructionRI   1 (r r0) (caddr a)
    Tac_load_ps r0 s        -> instructionRI   2 (r r0) (sym s)
    Tac_load_cs r0 a        -> instructionRI   3 (r r0) (caddr a)
    Tac_load_c r0 a         -> instructionRI   4 (r r0) (caddr a)
    Tac_load_f r0 fa        -> instructionRI   5 (r r0) (faddr fa)
    Tac_add r0 r1 r2        -> instructionRRR  6 (r r0) (r r1) (r r2)
    Tac_sub r0 r1 r2        -> instructionRRR  7 (r r0) (r r1) (r r2)
    Tac_mul r0 r1 r2        -> instructionRRR  8 (r r0) (r r1) (r r2)
    Tac_div r0 r1 r2        -> instructionRRR  9 (r r0) (r r1) (r r2)
    Tac_move r0 r1          -> instructionRRR 10 (r r0) (r r1) (i 0)
    Tac_call r0 fr n        -> instructionRRR 11 (r r0) (r fr) (i n)
    Tac_gen_ap r0 fr n      -> instructionRRR 12 (r r0) (r fr) (i n)
    Tac_tail_call fr n      -> instructionRRR 13 (i 0) (r fr) (i n)
    Tac_tail_gen_ap r0 fr n -> instructionRRR 14 (r r0) (r fr) (i n)
    Tac_part_ap r0 fr n     -> instructionRRR 15 (r r0) (r fr) (i n)
    Tac_jmp n               -> instructionRI  16 0 (i n)
    Tac_match r0 r1 r2      -> instructionRRR 17 (r r0) (r r1) (r r2)
    Tac_set_arg arg r1 n    -> instructionRRR 18 (i arg) (r r1) (i n)
    Tac_set_cl_val clr r1 n -> instructionRRR 19 (r clr) (r r1) (i n)
    Tac_eq r0 r1 r2         -> instructionRRR 20 (r r0) (r r1) (r r2)
    Tac_fun_header arity    -> instructionRI  63 (r 0) (i arity)


instBits, opcBits, regBits :: Int
instBits = 32
opcBits = 6
regBits = 5


-- an instruction containing a register and a number
instructionRI :: Int -> Int -> Int -> VMWord
instructionRI opcId register value =
  fromIntegral $
  (opcId `shiftL` (instBits - opcBits))
  .|. (register `shiftL` (instBits - (opcBits + regBits)))
  .|. value


-- an instruction containing three registers
instructionRRR :: Int -> Int -> Int -> Int -> VMWord
instructionRRR opcId r0 r1 r2 =
  fromIntegral $
  (opcId `shiftL` (instBits - opcBits))
  .|. (r0 `shiftL` (instBits - (opcBits + regBits)))
  .|. (r1 `shiftL` (instBits - (opcBits + 2 * regBits)))
  .|. (r2 `shiftL` (instBits - (opcBits + 3 * regBits)))




