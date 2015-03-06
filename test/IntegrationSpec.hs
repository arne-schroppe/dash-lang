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
