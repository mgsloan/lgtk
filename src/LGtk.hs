{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}
-- | Main LGtk interface.
module LGtk
    ( 
    -- * Re-export

    -- ** Category
      Category (..)

    -- ** Tensor
    , Tensor (..)

    -- ** Monad
    , liftM
    , liftM2
    , liftM3
    , when

    -- * Lenses
    -- ** Construction
    , Lens (Lens)
    , lens
    , iso

    -- ** Deconstruction
    , runLens
    , getL
    , setL
    , modL

    -- ** Pure lenses
    , fstLens
    , sndLens
    , listLens
    , maybeLens

    -- ** Impure lenses
    , showLens

    -- * Monad morphisms
    , Morph
    , HasReadPart (..)

    -- * References
    -- ** Basic operations
    , Reference
    , RefMonad
    , ReadRefMonad
    , readRef
    , writeRef
    , lensMap
    , joinRef
    , unitRef

    -- ** Reference creation
    , ExtRef
    , Ref
    , extRef
    , newRef
    , ReadRef
    , WriteRef
    , liftReadRef

    -- ** Derived constructs
    , modRef
    , readRef'
    , memoRead
    , undoTr

    , EqReference (..)
    , EqRef
    , eqRef
    , newEqRef
    , toRef

    -- * Dynamic networks
    , EffRef
    , onChange

    -- * I/O
    , SafeIO
    , getArgs
    , getProgName
    , lookupEnv

    , EffIORef
    , asyncWrite
    , putStr_
    , getLine_
    , fileRef

    -- ** Derived constructs
    , putStrLn_

    -- * GUI

    -- ** Running
    , Widget
    , runWidget

    -- ** GUI descriptions
    , label
    , checkbox
    , combobox
    , entry
    , vcat
    , hcat
    , button_
    , Color (..)
    , notebook
    , cell_
    , action
    , canvas
    , Dia
    , MouseEvent (..)
    , ScrollDirection (..)
    , hscale

    -- ** Derived constructs
    , empty
    , entryShow
    , button
    , smartButton
    , cell
    , cellNoMemo

    -- ** Experimental
    , button__

    ) where

import Data.Maybe
import Control.Category
import Control.Category.Product
import Control.Concurrent
import Control.Monad
import Control.Monad.State
import Control.Monad.Trans.Identity
import Prelude hiding ((.), id)
import Data.Lens.Common

import Control.Monad.ExtRef
import Control.Monad.Register
import Control.Monad.Register.Basic
import Control.Monad.EffRef
import GUI.Gtk.Structures hiding (Send, Receive, SendReceive, Widget)
import qualified GUI.Gtk.Structures as Gtk
import qualified GUI.Gtk.Structures.IO as Gtk
import Control.Monad.ExtRef.Pure
import Control.Monad.Restricted


{- |
Gtk widget descriptions.
Construction of a @(w :: forall m . EffIORef m => Widget m)@ value is side-effect free,
side-effects happen at running @('runWidget' w)@.

@Widget@ should be abstract data type, but it is also safe to keep it as a type synonym because
the operations of the revealed implementation are hidden.
-}
type Widget m = Gtk.Widget (EffectM m) m

{- |
Run a Gtk widget description.

The widget is shown in a window and the thread enters into the Gtk event cycle.
It leaves the event cycle when the window is closed.
-}
runWidget :: (forall m . EffIORef m => Widget m) -> IO ()
runWidget desc = do
    postActionsRef <- newRef' $ return ()
    let addPostAction  = runMorphD postActionsRef . modify . flip (>>)
        runPostActions = join $ runMorphD postActionsRef $ state $ \m -> (m, return ())
    actionChannel <- newChan
    _ <- forkIO $ forever $ do
        join $ readChan actionChannel
        runPostActions
    Gtk.gtkContext $ \postGUISync -> do
        widget <- runExtRef_ $ unliftIO $ \unlift ->
            evalRegister
                (runIdentityT $ Gtk.runWidget unlift addPostAction postGUISync desc)
                (liftIO . writeChan actionChannel . unlift)
        runPostActions
        return widget

-- | Vertical composition of widgets.
vcat :: [Widget m] -> Widget m
vcat = List Vertical

-- | Horizontal composition of widgets.
hcat :: [Widget m] -> Widget m
hcat = List Horizontal

-- | Empty widget.
empty :: Widget m
empty = hcat []

-- | Dynamic label.
label :: EffRef m => ReadRef m String -> Widget m
label = Label . rEffect True

-- | Low-level button with changeable background color.
button__
    :: EffRef m
    => ReadRef m String     -- ^ dynamic label of the button
    -> ReadRef m Bool       -- ^ the button is active when this returns @True@
    -> ReadRef m Color      -- ^ dynamic background color
    -> WriteRef m ()        -- ^ the action to do when the button is pressed
    -> Widget m
button__ r x c y = Button (rEffect True r) (rEffect True x) (rEffect True c) (toReceive $ \() -> y)

-- | Low-level button.
button_
    :: EffRef m
    => ReadRef m String     -- ^ dynamic label of the button
    -> ReadRef m Bool       -- ^ the button is active when this returns @True@
    -> WriteRef m ()        -- ^ the action to do when the button is pressed
    -> Widget m
button_ r x y = Button (rEffect True r) (rEffect True x) (const $ return ()) (toReceive $ \() -> y)

button
    :: EffRef m
    => ReadRef m String     -- ^ dynamic label of the button
    -> ReadRef m (Maybe (WriteRef m ()))     -- ^ when the @Maybe@ value is @Nothing@, the button is inactive
    -> Widget m
button r fm = button_ r (liftM isJust fm) (liftReadPart fm >>= maybe (return ()) id)



smartButton
    :: (EffRef m, EqReference r, RefMonad r ~ RefMonad (Ref m)) 
    => ReadRef m String     -- ^ dynamic label of the button
    -> r a              -- ^ underlying reference
    -> (a -> a)   -- ^ The button is active when this function is not identity on value of the reference. When the button is pressed, the value of the reference is modified with this function.
    -> Widget m
smartButton s r f
    = button_ s (hasEffect r f) (modRef r f)

-- | Checkbox.
checkbox :: EffRef m => Ref m Bool -> Widget m
checkbox r = Checkbox (rEffect True (readRef r), toReceive $ writeRef r)

-- | Simple combo box.
combobox :: EffRef m => [String] -> Ref m Int -> Widget m
combobox ss r = Combobox ss (rEffect True (readRef r), toReceive $ writeRef r)

-- | Text entry.
entry :: (EffRef m, Reference r, RefMonad r ~ RefMonad (Ref m))  => r String -> Widget m
entry r = Entry (rEffect True (readRef r), toReceive $ writeRef r)

-- | Text entry.
entryShow :: (EffRef m, Show a, Read a, Reference r, RefMonad r ~ RefMonad (Ref m)) => r a -> Widget m
entryShow r = entry $ showLens `lensMap` r

{- | Notebook (tabs).

The tabs are created lazily.
-}
notebook :: EffRef m => [(String, Widget m)] -> Widget m
notebook xs = Action $ do
    currentPage <- newRef 0
    let f index (title, w) = (,) title $ cell (liftM (== index) $ readRef currentPage) $ \b -> case b of
           False -> hcat []
           True -> w
    return $ Notebook' (toReceive $ writeRef currentPage) $ zipWith f [0..] xs

{- | Dynamic cell.

The monadic action for inner widget creation is memoised in the first monad layer.
-}
cell_ :: (EffRef m, Eq a) => ReadRef m a -> (forall x . (Widget m -> m x) -> a -> m (m x)) -> Widget m
cell_ = Cell . onChange True

{- | Dynamic cell.

The inner widgets are memoised.
-}
cell :: (EffRef m, Eq a) => ReadRef m a -> (a -> Widget m) -> Widget m
cell r m = cell_ r $ \mk -> liftM return . mk . m

{- | Dynamic cell.

The inner widgets are not memoised.
-}
cellNoMemo :: (EffRef m, Eq a) => ReadRef m a -> (a -> Widget m) -> Widget m
cellNoMemo r m = cell_ r $ \mk -> return . mk . m

-- | @action@ makes possible to do any 'EffRef' action while creating the widget.
action :: EffRef m => m (Widget m) -> Widget m
action = Action

canvas :: (EffRef m, Eq b) => Int -> Int -> Double -> (MouseEvent -> WriteRef m ()) -> ReadRef m b -> (b -> Dia) -> Widget m
canvas w h sc me r f = Canvas w h sc (toReceive me) (rEffect True r) f
 -- = cellNoMemo r $ Canvas_ w h sc . f  -- Canvas f $ rEffect True r

hscale :: (EffRef m) => Double -> Double -> Double -> Ref m Double -> Widget m
hscale a b c r = Scale a b c (rEffect True $ readRef r, toReceive $ writeRef r)

