module IntegrationSpec where

import Test.Hspec

-- This is mainly a test of the code generator. But it is an integration test because
-- we don't care about the instructions it churns out, as long as everything behaves as expected.

import Language.Spot.API
import Language.Spot.VM.Bits

import Numeric


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
      let result = run code
      result `shouldReturn` VMNumber 7

    -- TODO When returning a lambda from a function (as seen here) it would be more secure to have a tag for lambdas
    it "returns a simple lambda" $ do
      let code =  " val make-adder (x) = { \n\
                  \   val (y) = add 22 y \n\
                  \ } \n\
                  \ val adder = make-adder :nil \n\
                  \ adder 55"
      let result = run code
      result `shouldReturn` VMNumber 77


    it "returns a closure with a dynamic variable" $ do
      let code =  " val make-sub (x) = { \n\
                  \   val (y) = sub x y \n\
                  \ } \n\
                  \ val subtractor = make-sub 55 \n\
                  \ subtractor 4"
      let result = run code
      result `shouldReturn` VMNumber 51

    it "captures a constant number" $ do
      let code =  " val c = 30 \n\
                  \ val make-sub (x) = { \n\
                  \   val (y) = sub c y \n\
                  \ } \n\
                  \ val subtractor = make-sub 10 \n\
                  \ subtractor 4"
      let result = run code
      result `shouldReturn` VMNumber 26

    it "captures a constant plain symbol" $ do
      let code =  " val ps = :my-symbol \n\
                  \ val make-sym (x) = { \n\
                  \   val (y) = ps \n\
                  \ } \n\
                  \ val symbolicator = make-sym 44 \n\
                  \ symbolicator 55"
      let result = run code
      result `shouldReturn` VMSymbol "my-symbol" []

    it "captures a constant function" $ do
      let code =  " val subsub (a b) = sub a b \n\
                  \ val make-sub (x) = { \n\
                  \   val (y) = subsub x y \n\
                  \ } \n\
                  \ val subtractor = make-sub 10 \n\
                  \ subtractor 4"
      let result = run code
      result `shouldReturn` VMNumber 6

    it "captures several dynamic values" $ do
      let code =  " val make-sub (x y z w) = { \n\
                  \   val (a) = sub (sub z y) (sub x a)\n\
                  \ } \n\
                  \ val test = make-sub 33 55 99 160 \n\
                  \ test 24"
      let result = run code
      result `shouldReturn` VMNumber ( (99 - 55) - (33 - 24) ) -- result: 35

    it "supports nested closures" $ do
      let code = "\
      \ val outside = 1623 \n\
      \ val make-adder-maker (x) = {\n\
      \   val (y) = {\n\
      \     val (z) = {\n\
      \       add (add x (add z y)) outside \n\
      \ }\n\
      \ }\n\
      \ }\n\
      \ ((make-adder-maker 9) 80) 150"
      let result = run code
      result `shouldReturn` VMNumber 1862

    -- TODO test recursion, both top-level and inside a function

    context "when using compound symbols" $ do

      it "interprets a compound symbol" $ do
        let result = run ":sym 2 3"
        result `shouldReturn` VMSymbol "sym" [VMNumber 2, VMNumber 3]



{-
    context "when matching" $ do

      it "matches a value against a single number" $ do
        let code = " match 1 with {\n\
                   \   1 -> :one \n\
                   \ }"
        let result = run code
        result `shouldReturn` VMSymbol "one" []

      it "matches a value against numbers" $ do
        let code = " match 7 with {\n\
                   \   1 -> :one \n\
                   \   2 -> :two \n\
                   \   3 -> :three \n\
                   \   4 -> :four \n\
                   \   5 -> :five \n\
                   \   6 -> :six \n\
                   \   7 -> :seven \n\
                   \   8 -> :eight \n\
                   \ }"
        let result = run code
        result `shouldReturn` VMSymbol "seven" []

      it "matches a value against symbols" $ do
        let code = " match :two with {\n\
                   \   :one -> 1 \n\
                   \   :two -> 2 \n\
                   \ }"
        let result = run code
        result `shouldReturn` VMNumber 2

      it "matches a value against numbers inside a function" $ do
        let code = " val check (n) = { \n\
                   \   match n with { \n\
                   \     1 -> :one \n\
                   \     2 -> :two \n\
                   \ } \n\
                   \ } \n\
                   \ check 2"
        let result = run code
        result `shouldReturn` VMSymbol "two" []


      it "binds an identifier in a match pattern" $ do
        let code = " match 2 with { \n\
                   \   1 -> :one \n\
                   \   n -> add 5 n \n\
                   \ }"
        let result = run code
        result `shouldReturn` VMNumber 7


      it "matches a compound symbol" $ do
        let code =  " match (:test 4 8 15) with { \n\
                    \ :test 1 2 3 -> 1 \n\
                    \ :test 4 8 15 -> 2 \n\
                    \ :test 99 100 101 -> 3 \n\
                    \ }"
        let result = run code
        result `shouldReturn` VMNumber 2


      it "binds a value inside a symbol" $ do
        let code =  " match (:test 4 8 15) with { \n\
                    \ :test 1 2 3 -> 1 \n\
                    \ :test 4 n m -> add n m \n\
                    \ :test 99 100 101 -> 3 \n\
                    \ }"
        let result = run code
        result `shouldReturn` VMNumber 23


      it "binds a value inside a nested symbol" $ do
        let code =  " match :test 4 (:inner 8) 15 with { \n\
                    \ :test 4 (:wrong n) m -> 1 \n\
                    \ :test 4 (:inner n) m -> add n m \n\
                    \ :test 4 (:wrong n) m -> 1 \n\
                    \ }"
        let result = run code
        result `shouldReturn` VMNumber 23
-}


{-
What's missing:

K Closures
- Recursion (also mutual recursion)
- Currying (also with underscore)
- Creating symbols
- Modules
- Matching the same var multiple times (e.g.  :test a 4 a -> :something ... only works if symbol is e.g. :test "a" 4 "a")
- Faster, optimized match patterns (reduce number of comparisons)
- Uniquely name vars in frontend (?)
- Prevent duplicate var names in function definition (unless it's for pattern matching?)

TODO: Functions need a runtime tag!

-}

{-

-}

    {- TODO
      val make-sym (i) = 
        :sym i

      make-sym 4
    -}

