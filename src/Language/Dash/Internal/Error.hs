module Language.Dash.Internal.Error (
  CompilationError(..)
) where


-- TODO one constructor per error + show instance?
data CompilationError =
    InternalCompilerError String
  | CodeError String
  deriving (Eq)

instance Show CompilationError where
  show err =
    case err of
      InternalCompilerError msg -> "Internal compiler error: " ++ msg
      CodeError msg -> "Error: " ++ msg

