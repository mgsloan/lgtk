{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
module LGtk.Demos.Main
    ( main
    ) where

import Data.Maybe (isJust)
import Control.Lens
import Control.Monad

import LGtk

import LGtk.Demos.Tri
import LGtk.Demos.IntListEditor
import LGtk.Demos.TEditor

main :: IO ()
main = runWidget $ notebook
    [ (,) "Hello" $ label $ return "Hello World!"

    , (,) "Counters" $ notebook

        [ (,) "Unbounded" $ do
            c <- newEqRef 0
            vcat
                [ label $ liftM show $ readRef c
                , hcat
                    [ smartButton (return "+1") c (+1)
                    , smartButton (return "-1") c (+(-1))
                    ]
                ]

        , (,) "1..3" $ do
            c <- newEqRef 1
            vcat
                [ label $ liftM show $ readRef c
                , hcat
                    [ smartButton (return "+1") c $ min 3 . (+1)
                    , smartButton (return "-1") c $ max 1 . (+(-1))
                    ]
                ]

        , (,) "a..b" $ do
            ab <- newRef (1, 3)
            let (a, b) = interval ab
            c <- counter 0 ab
            vcat
                [ label $ liftM show $ readRef c
                , hcat
                    [ smartButton (return "+1") c (+1)
                    , smartButton (return "-1") c (+(-1))
                    ]
                , hcat [ label $ return "min", entryShow a ]
                , hcat [ label $ return "max", entryShow b ]
                ]

        ]

    , (,) "Buttons" $ do
        x <- newRef 0
        let is = [0, 65535 `div` 2, 65535]
            colorlist = liftM3 Color is is is
            f n = colorlist !! (n `mod` length colorlist)
        button__ (return "Push") (return True) (liftM f $ readRef x) $ modRef x (+1)

    , (,) "Tabs" $ notebook

        [ (,) "TabSwitch" $ do
            x <- newRef "a"
            let w = vcat [ label $ readRef x, entry x ]
            notebook
                [ (,) "T1" w
                , (,) "T2" w
                ]

        ]

    , (,) "Async" $ do
        ready <- newRef True
        delay <- newRef 1.0
        onChange False (readRef ready) $ \b -> return $ case b of
            True -> return ()
            False -> do
                d <- readRef' delay
                asyncWrite (ceiling $ 10^6 * d) (writeRef ready) True
        vcat
            [ hcat [ entryShow delay, label $ return "sec" ]
            , button_ (readRef delay >>= \d -> return $ "Start " ++ show d ++ " sec computation")
                      (readRef ready)
                      (writeRef ready False)
            , label $ liftM (\b -> if b then "Ready." else "Computing...") $ readRef ready
            ]

    , (,) "Timer" $ do
        t <- newRef 0
        onChange True (readRef t) $ \ti -> return $ asyncWrite (10^6) (writeRef t) (1 + ti) 
        vcat
            [ label $ liftM show $ readRef t
            ]

    , (,) "System" $ notebook

        [ (,) "Args" $ getArgs >>= \args -> label $ return $ unlines args

        , (,) "ProgName" $ getProgName >>= \args -> label $ return args

        , (,) "Env" $ do
            v <- newRef "HOME"
            lv <- newRef ""
            onChange True (readRef v) $ \s -> return $
                asyncWrite 0 (writeRef lv) =<< liftM (maybe "Not in env." show) (lookupEnv s)
            vcat
                [ entry v
                , label $ readRef lv
                ]

        , (,) "Std I/O" $ let
            put = do
                x <- newRef ""
                onChange False (readRef x) $ return . putStrLn_
                hcat 
                    [ label $ return "putStrLn"
                    , entry x
                    ]
            get = do
                ready <- newRef $ Just ""
                onChange False (liftM isJust $ readRef ready) $ \b -> 
                    return $ when (not b) $ getLine_ $ writeRef ready . Just
                hcat 
                    [ button_ (return "getLine") (liftM isJust $ readRef ready) $ writeRef ready Nothing
                    , label $ liftM (maybe "<<<waiting for input>>>" id) $ readRef ready
                    ]
           in vcat [ put, put, put, get, get, get ]
        ]

    , (,) "IntListEditor" $ do
        state <- fileRef "intListEditorState.txt"
        list <- extRef (justLens "" `lensMap` state) showLens []
        settings <- fileRef "intListEditorSettings.txt"
        range <- extRef (justLens "" `lensMap` settings) showLens True
        intListEditor (0, True) 15 list range

    , (,) "Tri" tri

    , (,) "T-Editor1" tEditor1

    , (,) "T-Editor3" $ newRef (iterate (Node Leaf) Leaf !! 10) >>= tEditor3

    ]

justLens :: a -> Lens' (Maybe a) a
justLens a = lens (maybe a id) (flip $ const . Just)

counter :: forall m a . (EffRef m, Ord a) => a -> Ref m (a, a) -> m (EqRef (RefCore m) a)
counter x ab = do
    c <- extRef ab (fix . _2) (x, (x, x))
    return $ fix . _1 `lensMap` eqRef c
  where
    fix :: Lens' (a, (a,a)) (a, (a,a))
    fix = lens id $ \_ (x, ab@(a, b)) -> (min b $ max a x, ab)

interval :: (Reference r, Ord a) => MRef r (a, a) -> (MRef r a, MRef r a)
interval ab = (lens fst set1 `lensMap` ab, lens snd set2 `lensMap` ab) where
    set1 (_, b) a = (min b a, b)
    set2 (a, _) b = (a, max a b)


