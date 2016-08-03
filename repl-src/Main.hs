import           Control.Monad.Trans       (liftIO)
import           Language.Dash.API
import           Language.Dash.Error.Error
import           Language.Dash.IR.Ast      (Expr (..))
import           System.Console.Haskeline
import           System.Environment
import           System.IO

data ReplState = ReplState {
  rsProg           :: Expr,
  rsMultilineMode  :: Bool,
  rsMultilineInput :: String
}

main = do
  putStrLn "Welcome to the dash repl\nType \".quit\" to quit\nUse \"...\" for multi line input (use a blank line to return to single line input)"
  let prog0 = either (error . show) id $ parseWithPreamble ":true" -- obtain preamble
  runInputT (setComplete noCompletion defaultSettings) $ loop $ ReplState prog0 False ""



loop :: ReplState -> InputT IO ()
loop state = do
  minput <- getInputLine $ if rsMultilineMode state then "… " else "> "
  case minput of
    Nothing -> return ()
    Just ".quit" -> return ()
    Just ".exit" -> return ()
    Just "..."   -> loop $ state { rsMultilineMode = True }
    Just ""      -> if rsMultilineMode state
                      then do prog' <- eval (rsMultilineInput state) (rsProg state)
                              loop $ state { rsMultilineMode = False, rsMultilineInput = "", rsProg = prog' }
                      else loop state
    Just input -> do state' <- if rsMultilineMode state
                               then return $ state { rsMultilineInput = (rsMultilineInput state) ++ "\n" ++ input }
                               else do prog' <- eval input (rsProg state)
                                       return $ state { rsProg = prog' }
                     loop state'

eval :: String -> Expr -> InputT IO Expr
eval input existingProg = do
  let parseResult = parseProgram input
  case parseResult of
    Left err -> outputStrLn (show err) >> return existingProg
    Right newProg -> do
      let combinedProg = appendExpr newProg existingProg
      result <- liftIO (runExpr combinedProg)
      case result of
        Left err -> do outputStrLn $ show err
                       return existingProg
        Right value -> do outputStrLn $ show value; return combinedProg


appendExpr :: Expr -> Expr -> Expr
appendExpr newExpr existingExpr =
  case existingExpr of
    LocalBinding b e -> LocalBinding b $ appendExpr newExpr e
    DestructAssignment pat boundExpr e -> DestructAssignment pat boundExpr $ appendExpr newExpr e
    _ -> newExpr


