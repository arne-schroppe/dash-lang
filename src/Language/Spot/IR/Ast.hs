module Language.Spot.IR.Ast (
  Pattern (..)
, Binding (..)
, Expr (..)
) where


data Pattern
    = PatNumber Int
    | PatVar String
    | PatSymbol String [Pattern]
    deriving (Show, Eq)


data Binding
    = Binding String Expr        -- name, body
    deriving (Show, Eq)

-- TODO rename 'FunCall' to Application or FunApplication?

data Expr
    = LitNumber Int
    | LitString String
    | LitSymbol String [Expr]
    | Var String
    | Namespace String Expr  -- TODO merge with var?
    | Lambda [String] Expr       -- arguments, body
    | FunCall Expr [Expr]
    | LocalBinding Binding Expr  -- binding, body
    | Module [Binding]
    | Match Expr [(Pattern, Expr)]
    deriving (Show, Eq)



