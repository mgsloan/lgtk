-- | This module exports unsafe definitions, like the @NewRef@ instance for @IO@ which does not fulfil the @NewRef@ laws in a multi-threaded environment.
module Control.MLens.Unsafe
    ( -- * Unsafe references
      fileRef
    ) where

import Data.MLens.Ref
import Control.MLens.NewRef.Unsafe ()


