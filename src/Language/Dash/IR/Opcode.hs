module Language.Dash.IR.Opcode (
  Opcode (..)
) where

import Language.Dash.IR.Data


-- TODO should we express known and unknown functions through separate types 
-- or data constructors?
data Opcode =
    OpcRet Reg
  | OpcLoadI Reg Int
  | OpcLoadAddr Reg ConstAddr
  | OpcLoadPS Reg SymId      -- load plain symbol
  | OpcLoadCS Reg ConstAddr  -- load compound symbol
  | OpcLoadC Reg ConstAddr   -- load constant
  | OpcLoadF Reg FuncAddr    -- load function address (code)
  | OpcAdd Reg Reg Reg
  | OpcSub Reg Reg Reg
  | OpcMul Reg Reg Reg
  | OpcDiv Reg Reg Reg
  | OpcMove Reg Reg
  | OpcCall Reg Reg Int
  | OpcGenAp Reg Reg Int
  | OpcTailCall Reg Int
  | OpcTailGenAp Reg Reg Int -- result reg (since this might do partial application)
                             -- , closure reg (heap), num args
  | OpcPartAp Reg Reg Int    -- result, reg with function address (code), num args
  | OpcJmp Int
  | OpcMatch Reg Reg Reg     -- subj reg, pattern addr reg, start reg for captures
  | OpcSetArg Int Reg Int
  | OpcSetClVal Reg Reg Int
  | OpcFunHeader Int         -- arity
  | OpcEq Reg Reg Reg
  | OpcCopySym Reg Reg
  | OpcSetSymField Reg Reg Int -- reg with heap symbol, reg of new value, index
  | OpcLoadStr Reg ConstAddr  -- load string
  | OpcStrLen Reg Reg
  | OpcLT Reg Reg Reg
  | OpcGT Reg Reg Reg
  deriving Show

