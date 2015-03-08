module IntegrationSpec where

import Test.Hspec

-- This is mainly a test of the code generator. But it is an integration test because
-- we don't care about the opcodes it churns out, as long as everything behaves as expected.

import Language.Spot.API
import Language.Spot.VM.Bits


spec :: Spec
spec = do
  describe "Spot" $ do

    it "evaluates an integer" $ do
      let result = run "4815"
      result `shouldReturn` VMNumber 4815

    it "evaluates a symbol" $ do
      let result = run ":spot"
      result `shouldReturn` VMSymbol "spot" []

    it "applies built-in add function" $ do
      let result = run "add 2 3"
      result `shouldReturn` VMNumber 5

    it "applies built-in subtract function" $ do
      let result = run "sub 7 3"
      result `shouldReturn` VMNumber 4

    it "interprets a symbol with values" $ do
      let result = run ":sym 2 3"
      result `shouldReturn` VMSymbol "sym" [VMNumber 2, VMNumber 3]

    it "stores a value in a variable" $ do
      let result = run " val a = 4\n\
                       \ a"
      result `shouldReturn` VMNumber 4

    it "uses local bindings in function call" $ do
      let code = " val a = 4 \n\
                 \ val b = 7 \n\
                 \ add a b"
      let result = run code
      result `shouldReturn` VMNumber 11

    it "applies a custom function" $ do
      let code = " val add-two (a) = {\n\
                 \   add 2 a \n\
                 \ } \n\
                 \ add-two 5"
      let result = run code
      result `shouldReturn` VMNumber 7

    it "applies a local variable to a custom function" $ do
      let code = " val add-two (a) = {\n\
                 \   add 2 a \n\
                 \ } \n\
                 \ val x = 10 \n\
                 \ val y = 5 \n\
                 \ add-two y"
      putStrLn $ show $ toAsm code
      let result = run code
      result `shouldReturn` VMNumber 7
