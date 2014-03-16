{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Control.Monad.Register.Basic
    ( evalRegister
    , evalRegisterBasic
    ) where

import Control.Monad
import Control.Monad.State
import Control.Monad.RWS
import Data.List

import Control.Monad.Restricted
import Control.Monad.Register
import Control.Monad.ExtRef

type Register m
    = RWST (m () -> m ()) (MonadMonoid m, Command -> MonadMonoid m) () m

instance NewRef m => MonadRegister (Register m) where

    type EffectM (Register m) = m

    liftEffectM = lift

    toReceive_ r unreg = do
        rr <- ask
--        unreg <- lift $ int $ rr . r
        tell $ t2 unreg
        return $ rr . r

    toSend_ init rb fb = do
        rr <- ask
        b <- lift rb
        v <- case init of
            False -> return $ Left b
            True -> lift $ do
                (c, (), (s1, ureg1)) <- runRWST (fb b) rr ()
                ((), (s2, ureg2)) <- execRWST c rr ()
                runMonadMonoid $ s1 `mappend` s2
                return $ Right [(b, (c, s1, s2, ureg1, ureg2))]
        memoref <- lift $ newRef' v
                            -- memo table, first item is the newest
        tell $ t1 $ do
            b <- rb
            join $ runMorphD memoref $ StateT $ \memo -> case memo of
                Left b' | b' == b -> return (return (), memo)
                Right ((b', (_, s1, s2, _, _)): _) | b' == b ->
                    return (runMonadMonoid $ s1 `mappend` s2, memo)
                _ -> do
                    case memo of
                        Right ((_, (_, _, _, ureg1, ureg2)): _) ->
                            runMonadMonoid $ ureg1 Block `mappend` ureg2 Kill
                        _ -> return ()
                    (c, (), (s1, ureg1)) <- case filter ((== b) . fst) $ either (const []) id memo of
                        ((_, (c, s1, _, ureg1, _)): _) -> do
                            runMonadMonoid $ ureg1 Unblock
                            return (c, (), (s1, ureg1))
                        _ -> runRWST (fb b) rr ()
                    ((), (s2, ureg2)) <- execRWST c rr ()
                    let memo' = Right $ (:) (b, (c, s1, s2, ureg1, ureg2)) $ filter ((/= b) . fst) $ either (const []) id memo
                    return (runMonadMonoid $ s1 `mappend` s2, memo')

t1 m = (MonadMonoid m, mempty)
t2 m = (mempty, MonadMonoid . m)

evalRegister :: forall k a . (NewRef k, ExtRef k, MonadIO k, SafeIO k)
    => (forall t . (MonadTrans t, MonadRegister (t k), MonadIO (t k)
       , ExtRef (t k), Ref (t k) ~ Ref k, EffectM (t k) ~ k, SafeIO (t k)) => t k a)
    -> (k () -> k ())
    -> k a
evalRegister m = evalRegister_ m

evalRegisterBasic
    :: forall k a . NewRef k
    => (forall t . (MonadTrans t, MonadRegister (t k)) => t k a)
    -> (k () -> k ())
    -> k a
evalRegisterBasic m = evalRegister_ m

evalRegister_
    :: NewRef k
    => (Register k a)
    -> (k () -> k ())
    -> k a
evalRegister_ m ch = do
    vx <- newRef' $ error "evalRegister"
    (a, (), reg) <- runRWST m (ch . (>> join (runMorphD vx get))) ()
    runMorphD vx $ put $ runMonadMonoid $ fst reg
    return a



