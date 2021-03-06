{-# LANGUAGE CPP #-}
{-# LANGUAGE RankNTypes #-}
-- | Default implementation. Points to either to the pure or the fast implementation depending on the cabal flag @PURE@.
module Data.LensRef.Default
    ( RefReader
    , RefCreator
    , RefWriter
    , runRefCreator
    ) where

#ifdef __PURE__
import Data.LensRef.Pure
#else
import Data.LensRef.Fast
#endif

