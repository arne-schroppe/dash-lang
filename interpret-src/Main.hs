import           Control.Monad
import           System.Environment
import           System.IO

import           Language.Dash.API

main = do
  args <- getArgs
  when ( (length args) == 0) $ error "Expected script path"
  let scriptPath = args !! 0
  fileContent <- readFile scriptPath
  result <- run fileContent
  print result
