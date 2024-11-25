// Copyright (c) Meta Platforms, Inc. and affiliates.

using System;
using System.Collections;
using System.Collections.Generic;
using JetBrains.Annotations;
using Oculus.Interaction;
using Oculus.Interaction.DistanceReticles;
using UnityEngine;
using UnityEngine.UIElements.Experimental;
using static WorldBeyondManager;
using Random = UnityEngine.Random;

public class WorldBeyondManager : MonoBehaviour
{
    static public WorldBeyondManager Instance = null;

    [Header("Scene Preview")]
    [SerializeField] private OVRSceneManager _sceneManager;
    [SerializeField] private OVRPassthroughLayer _passthroughLayer;
    bool _sceneModelLoaded = false;
    float _floorHeight = 0.0f;
    // after the Scene has been loaded successfuly, we still wait a frame before the data has "settled"
    // e.g. VolumeAndPlaneSwitcher needs to happen first, and script execution order also isn't fixed by default
    int _frameWait = 0;

    [HideInInspector]
    public OVRSceneAnchor[] _sceneAnchors;

    [Header("Game Pieces")]
    [HideInInspector]
    public VirtualRoom _vrRoom;
    public LightBeam _lightBeam;

   
    public GameObject _worldShockwave;
    public Material[] _environmentMaterials;

    [Header("Overlays")]
    public Camera _mainCamera;
    public MeshRenderer _fadeSphere;
    GameObject _backgroundFadeSphere;

    PassthroughStylist _passthroughStylist;
    Color _cameraDark = new Color(0, 0, 0, 0.75f);

    [Header("Hands")]
    public OVRSkeleton _leftHand;
    public OVRSkeleton _rightHand;
    OVRHand _leftOVR;
    OVRHand _rightOVR;
    public Transform _leftHandAnchor;
    public Transform _rightHandAnchor;
    public OVRInput.Controller _gameController { get; private set; }
    // hand input for grabbing is handled by the Interaction SDK
    // otherwise, we track some basic custom poses (palm up/out, hand closed)
    public bool _usingHands { get; private set; }
    bool _handClosed = false;
    public delegate void OnHand();
    public OnHand OnHandOpenDelegate;
    public OnHand OnHandClosedDelegate;
    public OnHand OnHandDelegate;
    [HideInInspector]
    public float _fistValue = 0.0f;
    public HandVisual _leftHandVisual;
    public HandVisual _rightHandVisual;
    public HandWristOffset _leftPointerOffset;
    public HandWristOffset _rightPointerOffset;

    public DistantInteractionLineVisual _interactionLineLeft;
    public DistantInteractionLineVisual _interactionLineRight;

    private float _leftHandGrabbedBallLastDistance = Mathf.Infinity;
    private float _rightHandGrabbedBallLastDistance = Mathf.Infinity;

    public bool isInVoid = false;
    public bool oppyBaitsYou = false;
    public bool searchForOppy = false;


    private void Awake()
    {
        if (!Instance)
        {
            Instance = this;
        }

        isInVoid = true; //_currentChapter = GameChapter.Void;

        _gameController = OVRInput.Controller.RTouch;
        _fadeSphere.gameObject.SetActive(true);
        _fadeSphere.sharedMaterial.SetColor("_Color", Color.black);

        // copy the black fade sphere to be behind the intro title
        // this shouldn't be necessary once color controls can be added to color PT
        _backgroundFadeSphere = Instantiate(_fadeSphere.gameObject, _fadeSphere.transform.parent);

        _usingHands = false;
        _leftOVR = _leftHand.GetComponent<OVRHand>();
        _rightOVR = _rightHand.GetComponent<OVRHand>();

        _passthroughLayer.colorMapEditorType = OVRPassthroughLayer.ColorMapEditorType.None;

        _passthroughLayer.textureOpacity = 0;
        _passthroughStylist = this.gameObject.AddComponent<PassthroughStylist>();
        _passthroughStylist.Init(_passthroughLayer);
        PassthroughStylist.PassthroughStyle darkPassthroughStyle = new PassthroughStylist.PassthroughStyle(
            new Color(0, 0, 0, 0),
            1.0f,
            0.0f,
            0.0f,
            0.0f,
            true,
            Color.black,
            Color.black,
            Color.black);
        _passthroughStylist.ForcePassthroughStyle(darkPassthroughStyle);
    }

    public void Start()
    {
#if UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_ANDROID
        OVRManager.eyeFovPremultipliedAlphaModeEnabled = false;
#endif

        if (MultiToy.Instance) MultiToy.Instance.InitializeToys();

        _sceneManager.SceneModelLoadedSuccessfully += SceneModelLoaded;
    }

    public void Update()
    {
        CalculateFistStrength();
        if (_handClosed)
        {
            if (_fistValue < 0.2f)
            {
                _handClosed = false;
                OnHandOpenDelegate?.Invoke();
            }
            else
            {
                OnHandDelegate?.Invoke();
            }
        }
        else
        {
            if (_fistValue > 0.3f)
            {
                _handClosed = true;
                OnHandClosedDelegate?.Invoke();
            }
        }

        var usingHands = (
                OVRInput.GetActiveController() == OVRInput.Controller.Hands ||
                OVRInput.GetActiveController() == OVRInput.Controller.LHand ||
                OVRInput.GetActiveController() == OVRInput.Controller.RHand ||
                OVRInput.GetActiveController() == OVRInput.Controller.None);
        if (usingHands != _usingHands)
        {
            _usingHands = usingHands;
            if (usingHands)
            {
                if (_gameController == OVRInput.Controller.LTouch)
                {
                    _gameController = OVRInput.Controller.LHand;
                }
                if (_gameController == OVRInput.Controller.RTouch)
                {
                    _gameController = OVRInput.Controller.RHand;
                }
            }
            else
            {
                if (_gameController == OVRInput.Controller.RHand)
                {
                    _gameController = OVRInput.Controller.RTouch;
                }
                if (_gameController == OVRInput.Controller.LHand)
                {
                    _gameController = OVRInput.Controller.LTouch;
                }
            }

            MultiToy.Instance.UseHands(_usingHands, _gameController == OVRInput.Controller.RTouch);
            MultiToy.Instance.EnableCollision(!_usingHands);

            // update tutorial text when switching input, if onscreen
            WorldBeyondTutorial.Instance.UpdateMessageTextForInput();
        }

        // constantly check if the player is within the polygonal floorplan of the room
        if (isInVoid==false)
        {
            if (!_vrRoom.IsPlayerInRoom())
            {
                WorldBeyondTutorial.Instance.DisplayMessage(WorldBeyondTutorial.TutorialMessage.ERROR_USER_WALKED_OUTSIDE_OF_ROOM);
            }
            else if (WorldBeyondTutorial.Instance._currentMessage == WorldBeyondTutorial.TutorialMessage.ERROR_USER_WALKED_OUTSIDE_OF_ROOM)
            {
                WorldBeyondTutorial.Instance.DisplayMessage(WorldBeyondTutorial.TutorialMessage.None);
            }
        }

        // disable a hand if it's not tracked (avoiding ghost hands)
        if (_leftOVR && _rightOVR)
        {
            _leftHandVisual.ForceOffVisibility = !_leftOVR.IsTracked;
            _rightHandVisual.ForceOffVisibility = !_rightOVR.IsTracked;
        }

        if (isInVoid)
        {
            if (_sceneModelLoaded) GetRoomFromScene();
        }else if (oppyBaitsYou)
        {
            //PositionTitleScreens(false);

            _backgroundFadeSphere.SetActive(false);
            PassthroughStylist.PassthroughStyle normalPassthrough = new PassthroughStylist.PassthroughStyle(
                   new Color(0, 0, 0, 0),
                   1.0f,
                   0.0f,
                   0.0f,
                   0.0f,
                   false,
                   Color.white,
                   Color.black,
                   Color.white);
            _passthroughStylist.ShowStylizedPassthrough(normalPassthrough, 5.0f);
            _fadeSphere.gameObject.SetActive(false);

            // if either hand is getting close to the toy, grab it and start the experience
            float handRange = 0.2f;
            float leftRange = Vector3.Distance(OVRInput.GetLocalControllerPosition(OVRInput.Controller.LTouch), MultiToy.Instance.transform.position);
            float rightRange = Vector3.Distance(OVRInput.GetLocalControllerPosition(OVRInput.Controller.RTouch), MultiToy.Instance.transform.position);
            bool leftHandApproaching = leftRange <= handRange;
            bool rightHandApproaching = rightRange <= handRange;

            MultiToy.Instance.ShowPassthroughGlove(true, _gameController == OVRInput.Controller.RTouch);
            oppyBaitsYou = false;
          
            searchForOppy = true;
            ForceChapter();// ForceChapter(GameChapter.SearchForOppy);
            SearchForOppy();         
        }
        bool flashlightActive = MultiToy.Instance.IsFlashlightActive();


        if (_usingHands)
        {
            HideInvisibleHandAccessories();
        }
    }

    /// <summary>
    /// Calculates whether each hand should be visible or not
    /// </summary>
    private void HideInvisibleHandAccessories()
    {
        bool leftHandHidden = !_leftHand.IsDataValid || _leftHandVisual.ForceOffVisibility;
        bool rightHandHidden = !_rightHand.IsDataValid || _rightHandVisual.ForceOffVisibility;
        var grabbedBall = MultiToy.Instance._grabbedBall;

        // Called before updating distance so that the hidden property is set while the ball is close to the hand
        UpdateHandVisibility(leftHandHidden, _interactionLineLeft, _leftHandGrabbedBallLastDistance, _gameController == OVRInput.Controller.LHand, grabbedBall);
        UpdateHandVisibility(rightHandHidden, _interactionLineRight, _rightHandGrabbedBallLastDistance, _gameController == OVRInput.Controller.RHand, grabbedBall);

        // Hidden hands have a position of 0, only update if the hand is visible.
        if (!leftHandHidden) _leftHandGrabbedBallLastDistance = grabbedBall ? Vector3.Distance(_leftHandAnchor.position, grabbedBall.transform.position) : Mathf.Infinity;
        if (!rightHandHidden) _rightHandGrabbedBallLastDistance = grabbedBall ? Vector3.Distance(_rightHandAnchor.position, grabbedBall.transform.position) : Mathf.Infinity;

        if (!_usingHands)
        {
            _interactionLineLeft.enabled = false;
            _interactionLineRight.enabled = false;
        }
    }

    /// <summary>
    /// Hides the ball, reticule and tutorial if the hand is not tracked anymore.
    /// Using previousHandToBallDistance to determine whether the current hand is holding the ball
    /// </summary>
    private void UpdateHandVisibility(bool handHidden, DistantInteractionLineVisual interactionLine, float previousHandToBallDistance, bool primary, [CanBeNull] BallCollectable grabbedBall)
    {
        bool holdingBall = grabbedBall != null && previousHandToBallDistance < 0.2f;
        if (handHidden)
        {
            interactionLine.gameObject.SetActive(false);
            if (primary) WorldBeyondTutorial.Instance.ForceInvisible();
            if (holdingBall) grabbedBall.ForceInvisible();
        }
        else
        {
            interactionLine.gameObject.SetActive(_usingHands && MultiToy.Instance.GetCurrentToy() == MultiToy.ToyOption.Flashlight);
            if (primary) WorldBeyondTutorial.Instance.ForceVisible();
            if (holdingBall) grabbedBall.ForceVisible();
        }
    }
    void OppyBaitsYou()
    {
        _passthroughStylist.ResetPassthrough(0.1f);
        StartCoroutine(PlaceToyRandomly(2.0f));
    }
    void SearchForOppy()
    {
        VirtualRoom.Instance.HideEffectMesh();
        _passthroughStylist.ResetPassthrough(0.1f);
        WorldBeyondEnvironment.Instance._sun.enabled = true;

        //---------------------THE MOST IMPORTANT CHUNK----------------------------------------------------------------------------------
        StartCoroutine(CountdownToFlashlight(0.1f)); //<-----------------------------COUNTDOWN TO TOY FUNCTIONALITY
        StartCoroutine(FlickerCameraToClearColor());//<-----------------------------THIS ACTUALLY MAKES THE PASSTHROUGH WORK!!!!!!!
    }
  
    public void ForceChapter()
    {
        StopAllCoroutines();
        KillControllerVibration();
        //MultiToy.Instance.SetToy(i);
        WorldBeyondEnvironment.Instance.ShowEnvironment(searchForOppy);

        if (isInVoid || oppyBaitsYou) _mainCamera.backgroundColor = _cameraDark; //(int)_currentChapter < (int)GameChapter.SearchForOppy)

       // _pet.gameObject.SetActive(oppyExplores || greatBeyond || ending); //(int)_currentChapter >= (int)GameChapter.OppyExploresReality
        int i = 0;
        if (isInVoid)
        {
            i = 0;
        }
        else if (oppyBaitsYou)
        {
            i = 3;
        }else if (searchForOppy)
        {
            i = 4;
        }

        MultiToy.Instance.SetToy(i);

        if (_lightBeam) { _lightBeam.gameObject.SetActive(false); }
    }

   
    /// <summary>
    /// When you first grab the MultiToy, the world flashes for a split second.
    /// </summary>
    IEnumerator FlickerCameraToClearColor()
    {
        float timer = 0.0f;
        float flickerTimer = 0.5f;
        while (timer <= flickerTimer)
        {
            timer += Time.deltaTime;
            float normTimer = Mathf.Clamp01(0.5f * timer / flickerTimer);
            _mainCamera.backgroundColor = Color.Lerp(Color.black, _cameraDark, MultiToy.Instance.EvaluateFlickerCurve(normTimer));
            if (timer >= flickerTimer)
            {
                VirtualRoom.Instance.ShowAllWalls(true);
                VirtualRoom.Instance.ShowDarkRoom(false);
                VirtualRoom.Instance.SetRoomSaturation(IsGreyPassthrough() ? 0 : 1);
                WorldBeyondEnvironment.Instance.ShowEnvironment(true);
            }
            yield return null;
        }
    }

    /// <summary>
    /// After a few seconds of playing with Oppy, unlock the wall toggler toy.
    /// </summary>
    IEnumerator UnlockWallToy(float countdown)
    {
        yield return new WaitForSeconds(countdown);
        MultiToy.Instance.UnlockWallToy();
        OVRInput.SetControllerVibration(1, 1, _gameController);
        yield return new WaitForSeconds(1.0f);
        KillControllerVibration();
    }

    /// <summary>
    /// Prepare the toy and light beam for their initial appearance.
    /// </summary>
    IEnumerator PlaceToyRandomly(float spawnTime)
    {
        yield return new WaitForSeconds(spawnTime);
        MultiToy.Instance.ShowToy(true);
        MultiToy.Instance.SetToyMesh(MultiToy.ToyOption.Flashlight);
    }

    /// <summary>
    /// Right after player grabs Multitoy, wait a few seconds before turning on the flashlight.
    /// </summary>
    IEnumerator CountdownToFlashlight(float spawnTime)
    {
        yield return new WaitForSeconds(spawnTime - 0.5f);
        OVRInput.SetControllerVibration(1, 1, _gameController);
        MultiToy.Instance.EnableFlashlightCone(true);
        if (_usingHands)
        {
            WorldBeyondTutorial.Instance.DisplayMessage(WorldBeyondTutorial.TutorialMessage.EnableFlashlight);
        }
        MultiToy.Instance._flashlightFlicker_1.Play();
        float timer = 0.0f;
        float lerpTime = 0.5f;
        while (timer <= lerpTime)
        {
            timer += Time.deltaTime;
            MultiToy.Instance.SetFlickerTime((0.5f * timer / lerpTime) + 0.5f);
            if (timer >= lerpTime)
            {
                MultiToy.Instance.SetFlickerTime(1.0f);
            }
            yield return null;
        }
        KillControllerVibration();
    }

    /// <summary>
    /// Called from OVRSceneManager.SceneModelLoadedSuccessfully().
    /// This only sets a flag, and the game behavior begins in Update().
    /// This is because OVRSceneManager does all the heavy lifting, and this experience requires it to be complete.
    /// </summary>
    void SceneModelLoaded()
    {
        _sceneModelLoaded = true;
    }

    /// <summary>
    /// When the Scene has loaded, instantiate all the wall and furniture items.
    /// OVRSceneManager creates proxy anchors, that we use as parent tranforms for these instantiated items.
    /// </summary>
    void GetRoomFromScene()
    {
        if (_frameWait < 1)
        {
            _frameWait++;
            return;
        }

        try
        {
            // OVRSceneAnchors have already been instantiated from OVRSceneManager
            // to avoid script execution conflicts, we do this once in the Update loop instead of directly when the SceneModelLoaded event is fired
            _sceneAnchors = FindObjectsOfType<OVRSceneAnchor>();

            // WARNING: right now, a Scene is guaranteed to have closed walls
            // if this ever changes, this logic needs to be revisited because the whole game fails (e.g. furniture with no walls)
            _vrRoom.Initialize(_sceneAnchors);

            // even though loading has succeeded to this point, do some sanity checks
            if (!_vrRoom.IsPlayerInRoom())
            {
                WorldBeyondTutorial.Instance.DisplayMessage(WorldBeyondTutorial.TutorialMessage.ERROR_USER_STARTED_OUTSIDE_OF_ROOM);
            }
            WorldBeyondEnvironment.Instance.Initialize();
            isInVoid = false;
            // isInTitle = true;
            oppyBaitsYou = true;
            ForceChapter(); //ForceChapter(GameChapter.Title);
            OppyBaitsYou();
        }
        catch
        {
            // if initialization messes up for some reason, quit the app
            WorldBeyondTutorial.Instance.DisplayMessage(WorldBeyondTutorial.TutorialMessage.ERROR_NO_SCENE_DATA);
        }
    }


    /// <summary>
    /// Self-explanatory.
    /// </summary>
    void KillControllerVibration()
    {
        OVRInput.SetControllerVibration(1, 0, _gameController);
    }

    /// <summary>
    /// Adjust the desaturation range of the environment shaders.
    /// </summary>
    void SetEnvironmentSaturation(float normSat)
    {
        // convert a normalized value to what the shader intakes
        float actualSat = Mathf.Lerp(1.0f, 0.08f, normSat);
        foreach (Material mtl in _environmentMaterials)
        {
            mtl.SetFloat("_SaturationDistance", actualSat);
        }
    }

    /// <summary>
    /// When a passthrough wall is first opened, the virtual environment appears greyscale to match Passthrough.
    /// Over a few seconds, the desaturation range shrinks.
    /// </summary>
    IEnumerator SaturateEnvironmentColor()
    {
        yield return new WaitForSeconds(4.0f);
        float timer = 0.0f;
        float lerpTime = 4.0f;
        while (timer <= lerpTime)
        {
            timer += Time.deltaTime;
            float normTime = IsGreyPassthrough() ? Mathf.Clamp01(timer / lerpTime) : 1.0f;
            SetEnvironmentSaturation(normTime);
            yield return null;
        }
    }

    /// <summary>
    /// Return a pose for the Multitoy, depending on controller type.
    /// </summary>
    public void GetDominantHand(ref Vector3 handPos, ref Quaternion handRot)
    {
        if (_usingHands)
        {
            bool L_hand = _gameController == OVRInput.Controller.LHand;
            OVRSkeleton refHand = (_gameController == OVRInput.Controller.LHand) ? _leftHand : _rightHand;
            Oculus.Interaction.HandVisual refHandVisual = (_gameController == OVRInput.Controller.LHand) ? _leftHandVisual : _rightHandVisual;
            if (refHandVisual.ForceOffVisibility)
            {
                return;
            }
            // if tuning these values, make your life easier by enabling the DebugAxis objects on the Multitoy prefab
            handPos = L_hand ? _leftPointerOffset.transform.position : _rightPointerOffset.transform.position;
            Vector3 handFwd = L_hand ? _leftPointerOffset.transform.rotation * _leftPointerOffset.Rotation * Vector3.up : _rightPointerOffset.transform.rotation * _rightPointerOffset.Rotation * Vector3.up;
            Vector3 handRt = (refHand.Bones[12].Transform.position - refHand.Bones[6].Transform.position) * (L_hand ? -1.0f : 1.0f);
            Vector3.OrthoNormalize(ref handFwd, ref handRt);
            Vector3 handUp = Vector3.Cross(handFwd, handRt);
            handRot = Quaternion.LookRotation(-handFwd, -handUp);
        }
        else
        {
            handPos = OVRInput.GetLocalControllerPosition(_gameController);
            handRot = OVRInput.GetLocalControllerRotation(_gameController);
        }
    }

    /// <summary>
    /// Simple 0-1 value to decide if the player has made a fist: if all fingers have "curled" enough.
    /// </summary>
    public void CalculateFistStrength()
    {
        OVRSkeleton refHand = (_gameController == OVRInput.Controller.LHand) ? _leftHand : _rightHand;
        Oculus.Interaction.HandVisual refHandVisual = (_gameController == OVRInput.Controller.LHand) ? _leftHandVisual : _rightHandVisual;
        if (!_usingHands || refHandVisual.ForceOffVisibility)
        {
            _fistValue = 1; // Hand is not visible, make it a fist to hide the flashlight and keep holding the held ball
            return;
        }
        Vector3 bone1 = (refHand.Bones[20].Transform.position - refHand.Bones[8].Transform.position).normalized;
        Vector3 bone2 = (refHand.Bones[21].Transform.position - refHand.Bones[11].Transform.position).normalized;
        Vector3 bone3 = (refHand.Bones[22].Transform.position - refHand.Bones[14].Transform.position).normalized;
        Vector3 bone4 = (refHand.Bones[23].Transform.position - refHand.Bones[18].Transform.position).normalized;
        Vector3 bone5 = (refHand.Bones[9].Transform.position - refHand.Bones[0].Transform.position).normalized;

        Vector3 avg = (bone1 + bone2 + bone3 + bone4) * 0.25f;
        _fistValue = Vector3.Dot(-bone5, avg.normalized) * 0.5f + 0.5f;
    }

    /// <summary>
    /// Self-explanatory
    /// </summary>
    public OVRSkeleton GetActiveHand()
    {
        if (_usingHands)
        {
            OVRSkeleton refHand = _gameController == OVRInput.Controller.LHand ? _leftHand : _rightHand;
            return refHand;
        }
        return null;
    }

    /// <summary>
    /// Get a transform for attaching the UI.
    /// </summary>
    public Transform GetControllingHand(int boneID)
    {
        bool usingLeft = _gameController == OVRInput.Controller.LTouch || _gameController == OVRInput.Controller.LHand;
        Transform hand = usingLeft ? _leftHandAnchor : _rightHandAnchor;
        if (_usingHands)
        {
            if (_rightHand && _leftHand)
            {
                // thumb tips, so menu is within view
                if (boneID >= 0 && boneID < _leftHand.Bones.Count)
                {
                    hand = usingLeft ? _leftHand.Bones[boneID].Transform : _rightHand.Bones[boneID].Transform;
                }
            }
        }
        return hand;
    }

    /// <summary>
    /// Someday, passthrough might be color...
    /// </summary>
    public bool IsGreyPassthrough()
    {
        // the headset identifier for Cambria has changed and will change last minute
        // this function serves to slightly change the color tuning of the experience depending on device
        // until things stabilize, force the EXPERIENCE to assume greyscale, but Passthrough itself is default to the device (line 124)
        // see this thread: https://fb.workplace.com/groups/272459344365710/permalink/479111297033846/
        return true;
    }

    /// <summary>
    /// Because of anchors, the ground floor may not be perfectly at y=0.
    /// </summary>
    public float GetFloorHeight()
    {
        return _floorHeight;
    }

    /// <summary>
    /// The floor is generally at y=0, but in cases where the Scene floor anchor isn't, shift the whole world.
    /// </summary>
    public void MoveGroundFloor(float height)
    {
        _floorHeight = height;
        WorldBeyondEnvironment.Instance.MoveGroundFloor(height);
    }
}
