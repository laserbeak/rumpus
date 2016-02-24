{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE DeriveDataTypeable #-}
module Rumpus.Systems.Controls where
import PreludeExtra
import Rumpus.Systems.PlayPause

data WorldEvent = GLFWEvent Event
                | VREvent VREvent
                deriving Show

data ControlsSystem = ControlsSystem
    { _ctsVRPal   :: !VRPal
    , _ctsPlayer  :: !(Pose GLfloat)
    , _ctsEvents  :: ![WorldEvent]
    , _ctsHeadPose :: !(Pose GLfloat) -- FIXME this should just update the entity in Hands
    }
makeLenses ''ControlsSystem
defineSystemKey ''ControlsSystem

initControlsSystem :: MonadState ECS m => VRPal -> m ()
initControlsSystem vrPal = do
    registerSystem sysControls $ ControlsSystem
            { _ctsVRPal = vrPal
            , _ctsPlayer = if gpRoomScale vrPal == RoomScale
                            then newPose
                            else newPose & posPosition .~ V3 0 1 3
            , _ctsEvents = []
            , _ctsHeadPose = newPose
            }


tickControlEventsSystem :: (MonadState ECS m, MonadIO m) => M44 GLfloat -> [Hand] -> [VREvent] -> m ()
tickControlEventsSystem headM44 hands vrEvents = modifySystemState sysControls $ do
    ctsHeadPose .= poseFromMatrix headM44

    vrPal@VRPal{..} <- use ctsVRPal

    -- Grab the old events for comparison
    lastEvents <- use ctsEvents

    
    -- Clear the events list
    ctsEvents .= map VREvent vrEvents

    -- Gather GLFW Pal events
    processEvents gpEvents $ \e -> do
        closeOnEscape gpWindow e
        ctsEvents %= (GLFWEvent e:)

    hands' <- if gpRoomScale == RoomScale
        then return hands
        else do
            player <- use ctsPlayer
            events <- use ctsEvents
            emulateRightHand vrPal player events

    -- Generate ButtonDown and ButtonUp events for Hand controllers. This should go in VRPal.
    let lastHands = mapMaybe (\case
            (VREvent (HandEvent _ (HandStateEvent hand))) -> Just hand
            _ -> Nothing) lastEvents

    let handTriples = zip3 lastHands hands' [LeftHand, RightHand]
    forM_ handTriples $ \(oldHand, newHand, whichHand) ->
        forM_ buttonPairs $ \(whichButton, buttonView) -> do
            let maybeEvent = case (buttonView oldHand, buttonView newHand) of
                    (True, False) -> Just ButtonUp
                    (False, True) -> Just ButtonDown
                    _             -> Nothing
            forM_ maybeEvent $ \buttonDownUp ->
                ctsEvents %= (VREvent (HandEvent whichHand (HandButtonEvent whichButton buttonDownUp)) :)

    ctsEvents <>= map VREvent
        ( HeadEvent headM44
        : zipWith ($) [HandEvent LeftHand, HandEvent RightHand] (map HandStateEvent hands')
        )

    use ctsEvents >>= mapM_ (\case
        VREvent (HandEvent _ (HandButtonEvent HandButtonStart ButtonDown)) -> lift toggleWorldPlaying
        GLFWEvent e -> onKeyDown e Key'Space (lift toggleWorldPlaying)
        _ -> return ())


emulateRightHand :: (MonadIO m) => VRPal -> Pose Float -> [WorldEvent] -> m [Hand]
emulateRightHand VRPal{..} player events  = do

    projM44     <- getWindowProjection gpWindow 45 0.1 1000
    mouseRay    <- cursorPosToWorldRay gpWindow projM44 player
    mouseState1 <- getMouseButton gpWindow MouseButton'1
    mouseState2 <- getMouseButton gpWindow MouseButton'2

    forM_ events $ \case
        GLFWEvent e -> onScroll e $ \_x y ->
            liftIO $ modifyIORef' gpEmulatedHandDepthRef (+ y)
        _ -> return ()
    handZ <- liftIO (readIORef gpEmulatedHandDepthRef)
    -- a <- getNow -- swap with line below to rotate hand for testing
    let a = 0
    let handPosition = projectRay mouseRay handZ
        trigger      = if mouseState1 == MouseButtonState'Pressed then 1 else 0
        grip         = mouseState2 == MouseButtonState'Pressed
        handMatrix   = transformationFromPose $ newPose
                                              & posPosition .~ handPosition
                                              & posOrientation .~ axisAngle (V3 0 1 0) a
        rightHand = emptyHand
                & hndMatrix  .~ handMatrix
                & hndTrigger .~ trigger
                & hndGrip    .~ grip
    return [emptyHand, rightHand]




buttonPairs :: [(HandButton, Hand -> Bool)]
buttonPairs = [ (HandButtonGrip,    view hndGrip)
              , (HandButtonTrigger, view (hndTrigger . to (> 0.5)))
              , (HandButtonStart,   view hndButtonS)
              , (HandButtonJoy,     view hndButtonJ)
              , (HandButtonA,       view hndButtonA)
              , (HandButtonB,       view hndButtonB)
              ]

withLeftHandEvents :: MonadState ECS m => (HandEvent -> m ()) -> m ()
withLeftHandEvents f = withSystem_ sysControls $ \controlSystem -> do
  let events = controlSystem ^. ctsEvents
  forM_ events (\e -> onLeftHandEvent e f)

withRightHandEvents :: MonadState ECS m => (HandEvent -> m ()) -> m ()
withRightHandEvents f = withSystem_ sysControls $ \controlSystem -> do
  let events = controlSystem ^. ctsEvents
  forM_ events (\e -> onRightHandEvent e f)

onLeftHandEvent :: Monad m => WorldEvent -> (HandEvent -> m ()) -> m ()
onLeftHandEvent (VREvent (HandEvent LeftHand handEvent)) f = f handEvent
onLeftHandEvent _ _ = return ()

onRightHandEvent :: Monad m => WorldEvent -> (HandEvent -> m ()) -> m ()
onRightHandEvent (VREvent (HandEvent RightHand handEvent)) f = f handEvent
onRightHandEvent _ _ = return ()


raycastCursorHits :: (MonadIO m, MonadState ECS m)
                  => Window -> DynamicsWorld -> M44 GLfloat -> m ()
raycastCursorHits window dynamicsWorld projMat = withSystem_ sysControls $ \controlSystem -> do
    let playerPose = controlSystem ^. ctsPlayer
    cursorRay <- cursorPosToWorldRay window projMat playerPose

    mRayResult <- rayTestClosest dynamicsWorld cursorRay
    forM_ mRayResult $ \rayResult -> do
        bodyID <- getCollisionObjectID (rrCollisionObject rayResult)
        -- Convert the hit location into model space
        -- (position, orientation) <- getBodyState (cube ^. cubBody)
        -- let model = mkTransformation orientation position
        --     pointOnModel = worldPointToModelPoint model (rrLocation rayResult)
        let _hitInWorld = rrLocation rayResult
            entityID = fromIntegral (unCollisionObjectID bodyID) :: EntityID
        return entityID
