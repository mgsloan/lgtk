{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE KindSignatures #-}
-- | Lens-based Gtk interface
module GUI.Gtk.Structures
    ( module GUI.Gtk.Structures
    , Color (..)
    ) where

import Data.Semigroup
import Graphics.UI.Gtk.Gdk.GC (Color (Color))
import Diagrams.Prelude (QDiagram, R2)
import Diagrams.Backend.Cairo (Cairo)

import Control.Monad.ExtRef

data KeyModifier = ShiftModifier | ControlModifier deriving (Eq, Ord)

shiftKeyModifier = ShiftModifier
controlKeyModifier = ControlModifier

type Dia a = QDiagram Cairo R2 a

data Send m a
    = Eq a => Send (ReadRef m a)
    | SendNothing

type Receive m a = a -> Control.Monad.ExtRef.Modifier m ()

runSend :: (EffRef m) => Send m a -> (a -> EffectM m ()) -> m ()
runSend SendNothing _ = return ()
runSend (Send r) f = rEffect r f >> return ()

noREffect = SendNothing

runReceive :: (EffRef m, Functor f) => f (Control.Monad.ExtRef.Modifier m ()) -> (Command -> EffectM m ()) -> m (f (EffectM m ()))
runReceive = toReceive

type SendReceive m a = (Send m a, Receive m a)

type Widget m = m (WidgetCore m)

-- | Widget descriptions
data WidgetCore m
    = Label (Send m String)     -- ^ label
    | Button { label_  :: Send m String
             , sensitive_ :: Send m Bool
             , color_ :: Send m Color
             , action_ :: Receive m ()
             }  -- ^ button
    | Checkbox (SendReceive m Bool)         -- ^ checkbox
    | Combobox [String] (SendReceive m Int) -- ^ combo box
    | Entry (SendReceive m String)          -- ^ entry field
    | List ListLayout [Widget m]         -- ^ group interfaces into row or column
    | Notebook' (Receive m Int) [(String, Widget m)]     -- ^ actual tab index, tabs
    | forall b . Eq b => Cell (Send m b) (forall x . (Widget m -> m x) -> b -> m (m x))
    | forall a b . (Eq b, Monoid a, Semigroup a) => Canvas Int Int Double (Receive m (MouseEvent a)) (Send m b) (b -> Dia a)
    | Scale Double Double Double (SendReceive m Double)


data ListLayout
    = Horizontal
    | Vertical
        deriving (Eq)

type ScrollDirection = ListLayout

data MouseEvent a
    = MoveTo (MousePos a)
    | MouseEnter (MousePos a)
    | MouseLeave (MousePos a)
    | Click (MousePos a)
    | DragTo (MousePos a)
    | Release (MousePos a)
    | ScrollTo ScrollDirection (MousePos a)
    | KeyPress [KeyModifier] String (Maybe Char)
    | LostFocus
        deriving (Eq)

data MousePos a
    = MousePos (Double, Double) a
        deriving (Eq)
