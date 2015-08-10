module Language.Dash.CodeGen.BuiltInDefinitions (
  builtInFunctions
, builtInSymbols
, bifStringConcatName
, tupleSymbolName
, listConsSymbolName
, listEmptySymbolName
, trueSymbolName
, falseSymbolName
) where

import           Language.Dash.IR.Data
import           Language.Dash.IR.Opcode



tupleSymbolName, listConsSymbolName, listEmptySymbolName, trueSymbolName, falseSymbolName :: String
trueSymbolName = "true"
falseSymbolName = "false"
tupleSymbolName = "tuple"
listConsSymbolName = "list"
listEmptySymbolName = "empty-list"

builtInSymbols :: [(String, SymId)]
builtInSymbols = [ (falseSymbolName, mkSymId 0)
                 , (trueSymbolName, mkSymId 1)

                  -- IO symbols
                  -- TODO prevent user from accessing these directly
                 , ("_io", mkSymId 2)
                 , ("_io-print-line", mkSymId 3)
                 , ("_io-read-line", mkSymId 4)
                 , ("_io-return", mkSymId 5)
                  -- end IO symbols
                 ]


bifStringConcatName, bifStringLengthName, bifSubStringName :: String
bifStringConcatName = "$string-concat"
bifStringLengthName = "string-length"
bifSubStringName = "sub-string"


-- TODO instead of "special" handling for primops, we could
-- also add a bif for every primop and then inline some functions
-- (e.g. those with less than n opcodes, etc)
builtInFunctions :: [(Name, Int, [Opcode])]
builtInFunctions = [  (bifStringConcatName, 2, [
                        OpcStrLen 2 0,
                        OpcStrLen 3 1,
                        OpcAdd 4 2 3,
                        OpcNewStr 5 4,
                        OpcLoadI 6 0,  -- index
                        OpcLoadI 7 1,
                        -- loop1:
                        OpcLT 8 2 6, -- is index >= length?
                        OpcJmpTrue 8 4, -- jmp next
                        OpcGetChar 9 0 6,
                        OpcPutChar 9 5 6,
                        OpcAdd 6 6 7,
                        OpcJmp (-6), -- jmp loop1
                        -- next:
                        OpcLoadI 6 0,
                        -- loop2:
                        OpcLT 8 3 6,
                        OpcJmpTrue 8 5, -- jmp done
                        OpcGetChar 9 1 6,
                        OpcAdd 10 2 6,
                        OpcPutChar 9 5 10,
                        OpcAdd 6 6 7,
                        OpcJmp (-7), -- jmp loop2
                        -- done:
                        OpcMove 0 5,
                        OpcRet 0
                      ]),
                      (bifStringLengthName, 1, [
                        OpcStrLen 0 0,
                        OpcRet 0
                      ]),
                      (bifSubStringName, 3, [ -- TODO truncate length if needed
                        OpcNewStr 3 1,
                        OpcLoadI 6 1,
                        OpcLoadI 7 0, -- counter
                        -- loop1:
                        OpcAdd 9 7 6,  -- TODO this is ugly. Fix our off-by-one error properly
                        OpcLT 4 1 9, -- is index >= length?
                        OpcJmpTrue 4 5, -- jmp next
                        OpcAdd 8 7 0,
                        OpcGetChar 5 2 8,
                        OpcPutChar 5 3 7,
                        OpcAdd 7 7 6,
                        OpcJmp (-8), -- jmp loop1
                        -- next:
                        OpcMove 0 3,
                        OpcRet 0
                      ]),
                      ("<=", 2, [
                        OpcLT 2 0 1,
                        OpcJmpTrue 2 1,
                        OpcEq 2 0 1,
                        OpcMove 0 2,
                        OpcRet 0
                      ]),
                      (">=", 2, [
                        OpcGT 2 0 1,
                        OpcJmpTrue 2 1,
                        OpcEq 2 0 1,
                        OpcMove 0 2,
                        OpcRet 0
                      ])
                   ]


{-
preamble :: String
preamble = "\n\
\ io-bind action next =  \n\
\   

-}

