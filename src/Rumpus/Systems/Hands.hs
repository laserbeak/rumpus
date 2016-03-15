{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE FlexibleContexts #-}
module Rumpus.Systems.Hands where
import Rumpus.Systems.Controls
import Rumpus.Systems.Physics
import Rumpus.Systems.Shared
import PreludeExtra
data HandsSystem = HandsSystem 
    { _hndLeftHand  :: EntityID
    , _hndRightHand :: EntityID
    --, _hndHead      :: EntityID
    } deriving Show
makeLenses ''HandsSystem

defineSystemKey ''HandsSystem

--tickHandsSystem = do

startHandsSystem :: (MonadState ECS m, MonadIO m) => m ()
startHandsSystem = do
    vrPal <- viewSystem sysControls ctsVRPal
    let handColor = V4 0.6 0.6 0.9 1
    --when (gpRoomScale vrPal == RoomScale) $ do

    leftHandID <- spawnEntity Transient $ do
        cmpColor             ==> handColor
        cmpSize              ==> V3 0.1 0.1 0.3
        cmpShapeType         ==> CubeShape
        cmpName              ==> "Left Hand"
        cmpPhysicsProperties ==> [IsKinematic, NoContactResponse]
        cmpMass              ==> 0
    rightHandID <- spawnEntity Transient $ do
        cmpColor             ==> handColor
        cmpSize              ==> V3 0.1 0.1 0.3
        cmpShapeType         ==> CubeShape
        cmpName              ==> "Right Hand"
        cmpPhysicsProperties ==> [IsKinematic, NoContactResponse]
        cmpMass              ==> 0

    registerSystem sysHands $ HandsSystem
            { _hndLeftHand  = leftHandID
            , _hndRightHand = rightHandID
            }

    return ()

-- FIXME should update and get hndHead instead
getHeadPose :: (MonadState ECS m) => m (M44 GLfloat)
getHeadPose = viewSystem sysControls ctsHeadPose

getLeftHandID :: (MonadState ECS m) => m EntityID
getLeftHandID  = viewSystem sysHands hndLeftHand
getRightHandID :: (MonadState ECS m) => m EntityID
getRightHandID = viewSystem sysHands hndLeftHand