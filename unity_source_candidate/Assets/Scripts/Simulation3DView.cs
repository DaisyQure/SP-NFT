using UnityEngine;

public class Simulation3DView : MonoBehaviour
{
    public Camera sceneCamera;
    public SimulationUI simulationUI;
    public Simulation3DTargetFeedback targetFeedback;
    public Transform shoulderPivot;
    public Transform forearmPivot;
    public Transform gunRoot;
    public Transform muzzlePoint;
    public Transform targetAimPoint;
    public Light muzzleFlashLight;
    public Renderer muzzleFlashRenderer;
    public AudioSource rifleFireAudioSource;
    public AudioClip rifleFireClip;
    public float muzzleFlashRendererDuration = 0.06f;
    public Vector3 cameraPosition = new Vector3(0f, 1.55f, -0.2f);
    public Vector3 cameraEuler = new Vector3(3f, 0f, 0f);
    public float recoilDuration = 0.18f;
    public float recoilKick = 9f;
    public bool overrideCameraOnPlay = false;

    [Header("Rifle Rig")]
    public Transform rifleRigRoot;
    public Transform rifleWeapon;
    public Transform rifleAimPoint;
    public Transform rifleFirePoint;
    public Transform rifleSwayPivot;
    public Vector3 rifleLoweredLocalPositionOffset = new Vector3(0.06f, -0.05f, 0.08f);
    public Vector3 rifleRaisedLocalPositionOffset = Vector3.zero;
    public Vector3 rifleLoweredLocalEulerOffset = new Vector3(7f, -8f, 6f);
    public Vector3 rifleRaisedLocalEulerOffset = Vector3.zero;

    [Header("Aim Assist")]
    [Range(0.1f, 1f)] public float aimAssistThresholdStart = 0.58f;
    [Range(0f, 1f)] public float aimAssistMaxBlend = 1f;
    public float maxAimAssistDegrees = 20f;
    public Vector3 rifleHoldLocalPositionOffset = new Vector3(-0.024f, 0.028f, -0.045f);
    public Vector3 rifleHoldLocalEulerOffset = new Vector3(-4.5f, 2.2f, -1.2f);
    [Range(0f, 1f)] public float holdSwayMultiplier = 0.08f;
    [Range(0f, 1f)] public float holdBreathingMultiplier = 0.14f;

    private SimulationGameManager simulation;
    private SimulationGameManager.TrialState lastState = SimulationGameManager.TrialState.Idle;
    private float recoilTimer;
    private float muzzleTimer;
    private float muzzleFlashRendererTimer;
    private Material generatedMuzzleFlashMaterial;
    private Vector3 rifleRigInitialLocalPosition;
    private Quaternion rifleRigInitialLocalRotation;
    private Vector3 rifleSwayInitialLocalPosition;
    private Quaternion rifleSwayInitialLocalRotation;

    void Start()
    {
        simulation = SimulationGameManager.Instance;
        simulationUI = simulationUI != null ? simulationUI : FindObjectOfType<SimulationUI>();
        if (simulationUI != null) simulationUI.hideLegacy2DVisuals = false;

        sceneCamera = sceneCamera != null ? sceneCamera : Camera.main;
        if (sceneCamera == null) sceneCamera = FindObjectOfType<Camera>();

        ResolveRifleRigReferences();
        ResolveTargetReferences();
        EnsureMuzzleFlashRenderer();
        EnsureRifleFireAudio();
        CacheInitialRigPose();
        ValidateSceneReferences();

        if (overrideCameraOnPlay)
        {
            ConfigureCamera();
        }

        if (simulation != null)
        {
            lastState = simulation.state;
        }
    }

    void Update()
    {
        if (simulation == null)
        {
            simulation = SimulationGameManager.Instance;
            if (simulation == null) return;
        }

        if (simulationUI != null) simulationUI.hideLegacy2DVisuals = false;

        AnimateRig();
        UpdateTransientFx();

        if (simulation.state != lastState)
        {
            if (simulation.state == SimulationGameManager.TrialState.Fired)
            {
                HandleFired();
            }
            lastState = simulation.state;
        }
    }

    void ResolveRifleRigReferences()
    {
        if (sceneCamera == null) return;

        Transform shooterRig = sceneCamera.transform.Find("Simulation3D_ShooterRig");
        if (shooterRig == null) return;

        if (rifleRigRoot == null) rifleRigRoot = FindChildRecursive(shooterRig, "Rifle_WeaponObject");
        if (rifleRigRoot == null) return;

        if (rifleWeapon == null) rifleWeapon = FindChildRecursive(rifleRigRoot, "Weapon");
        if (rifleAimPoint == null) rifleAimPoint = FindChildRecursive(rifleRigRoot, "AimPoint");
        if (rifleFirePoint == null) rifleFirePoint = FindChildRecursive(rifleRigRoot, "FirePoint");
        if (rifleSwayPivot == null) rifleSwayPivot = FindChildRecursive(rifleRigRoot, "SwayPivot");
        if (rifleFirePoint != null) muzzlePoint = rifleFirePoint;
    }

    void ResolveTargetReferences()
    {
        if (targetFeedback == null) targetFeedback = FindObjectOfType<Simulation3DTargetFeedback>();
        if (targetAimPoint == null && targetFeedback != null)
        {
            targetAimPoint = FindChildRecursive(targetFeedback.transform, "TargetAimPoint");
            if (targetAimPoint == null) targetAimPoint = targetFeedback.transform;
        }
    }

    void EnsureMuzzleFlashRenderer()
    {
        if (muzzlePoint == null || muzzleFlashRenderer != null) return;

        Transform existing = muzzlePoint.Find("MuzzleFlashVisual");
        if (existing == null)
        {
            var flash = GameObject.CreatePrimitive(PrimitiveType.Quad);
            flash.name = "MuzzleFlashVisual";
            flash.transform.SetParent(muzzlePoint, false);
            flash.transform.localPosition = new Vector3(0f, 0f, 0.08f);
            flash.transform.localRotation = Quaternion.identity;
            flash.transform.localScale = new Vector3(0.09f, 0.14f, 0.09f);
            var collider = flash.GetComponent<Collider>();
            if (collider != null) Destroy(collider);
            existing = flash.transform;
        }

        var renderer = existing.GetComponent<Renderer>();
        if (renderer == null) renderer = existing.gameObject.AddComponent<MeshRenderer>();

        var filter = existing.GetComponent<MeshFilter>();
        if (filter == null)
        {
            filter = existing.gameObject.AddComponent<MeshFilter>();
            filter.sharedMesh = Resources.GetBuiltinResource<Mesh>("Quad.fbx");
        }

        var material = CreateFallbackMuzzleFlashMaterial();
        if (material != null)
        {
            renderer.sharedMaterial = material;
        }

        renderer.enabled = false;
        muzzleFlashRenderer = renderer;
    }

    Material CreateFallbackMuzzleFlashMaterial()
    {
        if (generatedMuzzleFlashMaterial != null) return generatedMuzzleFlashMaterial;

        Shader shader = Shader.Find("Universal Render Pipeline/Unlit");
        if (shader == null) shader = Shader.Find("Unlit/Color");
        if (shader == null) return null;

        generatedMuzzleFlashMaterial = new Material(shader);
        if (generatedMuzzleFlashMaterial.HasProperty("_BaseColor"))
            generatedMuzzleFlashMaterial.SetColor("_BaseColor", new Color(1f, 0.88f, 0.45f, 0.9f));
        if (generatedMuzzleFlashMaterial.HasProperty("_Color"))
            generatedMuzzleFlashMaterial.SetColor("_Color", new Color(1f, 0.88f, 0.45f, 0.9f));
        if (generatedMuzzleFlashMaterial.HasProperty("_Surface"))
            generatedMuzzleFlashMaterial.SetFloat("_Surface", 1f);
        if (generatedMuzzleFlashMaterial.HasProperty("_Blend"))
            generatedMuzzleFlashMaterial.SetFloat("_Blend", 0f);
        if (generatedMuzzleFlashMaterial.HasProperty("_SrcBlend"))
            generatedMuzzleFlashMaterial.SetFloat("_SrcBlend", 5f);
        if (generatedMuzzleFlashMaterial.HasProperty("_DstBlend"))
            generatedMuzzleFlashMaterial.SetFloat("_DstBlend", 10f);
        if (generatedMuzzleFlashMaterial.HasProperty("_ZWrite"))
            generatedMuzzleFlashMaterial.SetFloat("_ZWrite", 0f);
        if (generatedMuzzleFlashMaterial.HasProperty("_Cull"))
            generatedMuzzleFlashMaterial.SetFloat("_Cull", 0f);
        generatedMuzzleFlashMaterial.renderQueue = 3000;
        return generatedMuzzleFlashMaterial;
    }

    void EnsureRifleFireAudio()
    {
        if (rifleFireAudioSource != null) return;

        GameObject audioObject = GameObject.Find("RifleFireAudio");
        if (audioObject == null)
        {
            audioObject = new GameObject("RifleFireAudio");
            if (sceneCamera != null)
            {
                audioObject.transform.SetParent(sceneCamera.transform, false);
            }
        }

        rifleFireAudioSource = audioObject.GetComponent<AudioSource>();
        if (rifleFireAudioSource == null)
        {
            rifleFireAudioSource = audioObject.AddComponent<AudioSource>();
        }

        rifleFireAudioSource.playOnAwake = false;
        rifleFireAudioSource.loop = false;
        rifleFireAudioSource.spatialBlend = 0f;
        rifleFireAudioSource.volume = 1f;
    }

    void CacheInitialRigPose()
    {
        if (rifleRigRoot != null)
        {
            rifleRigInitialLocalPosition = rifleRigRoot.localPosition;
            rifleRigInitialLocalRotation = rifleRigRoot.localRotation;
        }

        if (rifleSwayPivot != null)
        {
            rifleSwayInitialLocalPosition = rifleSwayPivot.localPosition;
            rifleSwayInitialLocalRotation = rifleSwayPivot.localRotation;
        }
    }

    void ValidateSceneReferences()
    {
        if (sceneCamera == null) Debug.LogWarning("[Simulation3DView] Missing sceneCamera reference.");
        if (targetFeedback == null) Debug.LogWarning("[Simulation3DView] Missing targetFeedback reference.");
        if (targetAimPoint == null) Debug.LogWarning("[Simulation3DView] Missing targetAimPoint reference.");
        if (muzzleFlashLight == null) Debug.LogWarning("[Simulation3DView] Missing muzzleFlashLight reference.");
        if (muzzleFlashRenderer == null) Debug.LogWarning("[Simulation3DView] Missing muzzleFlashRenderer reference.");
        if (rifleFireClip == null)
        {
            Debug.Log("[Simulation3DView] No fire audio clip assigned; using silent redistributable placeholder mode.");
        }

        bool hasRifleRig = rifleRigRoot != null && rifleSwayPivot != null;
        bool hasLegacyRig = shoulderPivot != null && forearmPivot != null && gunRoot != null;
        if (!hasRifleRig && !hasLegacyRig)
        {
            Debug.LogWarning("[Simulation3DView] No usable front rig found.");
        }
    }

    void ConfigureCamera()
    {
        if (sceneCamera == null) return;
        sceneCamera.transform.position = cameraPosition;
        sceneCamera.transform.rotation = Quaternion.Euler(cameraEuler);
        sceneCamera.orthographic = false;
        sceneCamera.fieldOfView = 56f;
        sceneCamera.clearFlags = CameraClearFlags.SolidColor;
        sceneCamera.backgroundColor = new Color(0.08f, 0.1f, 0.14f, 1f);
    }

    void AnimateRig()
    {
        if (rifleRigRoot != null && rifleSwayPivot != null)
        {
            AnimateRifleRig();
            return;
        }

        AnimateLegacyRig();
    }

    void AnimateRifleRig()
    {
        float aimT = Mathf.Clamp01(simulation.currentIntensity);
        float threshold = Mathf.Max(simulation.threshold, 0.01f);
        float thresholdT = Mathf.InverseLerp(0f, threshold, simulation.currentIntensity);
        float nearThresholdT = Mathf.InverseLerp(threshold * aimAssistThresholdStart, threshold, simulation.currentIntensity);
        nearThresholdT = Mathf.SmoothStep(0f, 1f, nearThresholdT);
        float holdProgressT = Mathf.Clamp01(simulation.aboveThresholdDuration / Mathf.Max(simulation.holdTimeSec, 0.01f));
        if (simulation.state == SimulationGameManager.TrialState.ReadyToFire || simulation.state == SimulationGameManager.TrialState.Fired)
            holdProgressT = 1f;

        float aimAssistT = Mathf.Clamp01(Mathf.Max(nearThresholdT * aimT, holdProgressT) * aimAssistMaxBlend);
        float holdLockT = Mathf.Clamp01(Mathf.Max(holdProgressT, simulation.state == SimulationGameManager.TrialState.ReadyToFire ? 1f : 0f));
        float lockBiasT = Mathf.Clamp01(Mathf.Max(holdLockT, nearThresholdT * 0.65f));

        float swayAmplitude = Mathf.Lerp(0.9f, 0.15f, thresholdT) * Mathf.Lerp(1f, holdSwayMultiplier, aimAssistT);
        float sway = Mathf.Sin(Time.time * Mathf.Lerp(1.5f, 3.8f, 1f - thresholdT)) * swayAmplitude;
        float breathing = Mathf.Sin(Time.time * 1.1f)
            * Mathf.Lerp(0.012f, 0.005f, aimT)
            * Mathf.Lerp(1f, holdBreathingMultiplier, aimAssistT);
        float recoil = recoilTimer > 0f ? Mathf.Sin((1f - recoilTimer / recoilDuration) * Mathf.PI) * recoilKick : 0f;

        Vector3 posePositionOffset = Vector3.Lerp(rifleLoweredLocalPositionOffset, rifleRaisedLocalPositionOffset, aimT)
            + Vector3.Lerp(Vector3.zero, rifleHoldLocalPositionOffset, lockBiasT);
        Vector3 poseEulerOffset = Vector3.Lerp(rifleLoweredLocalEulerOffset, rifleRaisedLocalEulerOffset, aimT)
            + Vector3.Lerp(Vector3.zero, rifleHoldLocalEulerOffset, lockBiasT);

        rifleRigRoot.localPosition = rifleRigInitialLocalPosition + posePositionOffset;
        rifleRigRoot.localRotation = rifleRigInitialLocalRotation * Quaternion.Euler(poseEulerOffset);
        ApplyAimConvergence(aimAssistT);

        rifleSwayPivot.localRotation = rifleSwayInitialLocalRotation * Quaternion.Euler(-recoil * 0.4f, sway * 0.9f, sway * 0.35f);
        rifleSwayPivot.localPosition = rifleSwayInitialLocalPosition + new Vector3(0f, breathing, -recoil * 0.0012f);
    }

    void ApplyAimConvergence(float aimAssistT)
    {
        if (aimAssistT <= 0f || rifleRigRoot == null) return;

        Transform sourcePoint = rifleAimPoint != null ? rifleAimPoint : rifleFirePoint;
        Transform targetPoint = targetAimPoint != null ? targetAimPoint : targetFeedback != null ? targetFeedback.transform : null;
        if (sourcePoint == null || targetPoint == null) return;

        Vector3 targetDirection = targetPoint.position - sourcePoint.position;
        if (targetDirection.sqrMagnitude < 0.0001f) return;
        targetDirection.Normalize();

        Quaternion fullCorrection = Quaternion.FromToRotation(sourcePoint.forward, targetDirection);
        Quaternion limitedCorrection = Quaternion.RotateTowards(Quaternion.identity, fullCorrection, maxAimAssistDegrees);
        Quaternion blendedCorrection = Quaternion.Slerp(Quaternion.identity, limitedCorrection, aimAssistT);
        rifleRigRoot.rotation = blendedCorrection * rifleRigRoot.rotation;
    }

    void AnimateLegacyRig()
    {
        if (shoulderPivot == null || forearmPivot == null || gunRoot == null) return;

        float aimT = Mathf.Clamp01(simulation.currentIntensity);
        float thresholdT = Mathf.InverseLerp(0f, Mathf.Max(simulation.threshold, 0.01f), simulation.currentIntensity);
        float swayAmplitude = Mathf.Lerp(1.2f, 0.2f, thresholdT);
        float sway = Mathf.Sin(Time.time * Mathf.Lerp(1.6f, 4.2f, 1f - thresholdT)) * swayAmplitude;
        float breathing = Mathf.Sin(Time.time * 1.1f) * Mathf.Lerp(0.015f, 0.006f, aimT);
        float recoil = recoilTimer > 0f ? Mathf.Sin((1f - recoilTimer / recoilDuration) * Mathf.PI) * recoilKick : 0f;

        shoulderPivot.localRotation = Quaternion.Euler(
            Mathf.Lerp(24f, 8f, aimT) - recoil * 0.45f,
            Mathf.Lerp(-10f, -3f, aimT),
            Mathf.Lerp(6f, 1.5f, aimT) + sway);

        forearmPivot.localRotation = Quaternion.Euler(
            Mathf.Lerp(6f, -2f, aimT) - recoil * 0.2f,
            0f,
            sway * 0.35f);

        gunRoot.localRotation = Quaternion.Euler(-2f, sway * 0.15f, 0f);
        gunRoot.localPosition = new Vector3(0.02f, 0.03f + breathing, 0.5f - recoil * 0.0012f);
    }

    void UpdateTransientFx()
    {
        if (recoilTimer > 0f)
        {
            recoilTimer -= Time.deltaTime;
            if (recoilTimer < 0f) recoilTimer = 0f;
        }

        if (muzzlePoint != null)
        {
            if (muzzleFlashLight != null)
            {
                muzzleFlashLight.transform.position = muzzlePoint.position;
                muzzleFlashLight.transform.rotation = muzzlePoint.rotation;
            }

            if (muzzleFlashRenderer != null)
            {
                muzzleFlashRenderer.transform.position = muzzlePoint.position + muzzlePoint.forward * 0.03f;
                muzzleFlashRenderer.transform.rotation = sceneCamera != null ? sceneCamera.transform.rotation : muzzlePoint.rotation;
            }
        }

        if (muzzleFlashRenderer != null)
        {
            if (muzzleFlashRendererTimer > 0f)
            {
                muzzleFlashRendererTimer -= Time.deltaTime;
                if (muzzleFlashRendererTimer <= 0f)
                {
                    muzzleFlashRenderer.enabled = false;
                }
            }
            else if (muzzleFlashRenderer.enabled)
            {
                muzzleFlashRenderer.enabled = false;
            }
        }

        if (muzzleFlashLight != null)
        {
            if (muzzleTimer > 0f)
            {
                muzzleTimer -= Time.deltaTime;
                muzzleFlashLight.intensity = Mathf.Lerp(0f, 6f, muzzleTimer / 0.08f);
                if (muzzleTimer <= 0f) muzzleFlashLight.intensity = 0f;
            }
            else
            {
                muzzleFlashLight.intensity = 0f;
            }
        }
    }

    void HandleFired()
    {
        recoilTimer = recoilDuration;
        muzzleTimer = 0.08f;
        muzzleFlashRendererTimer = muzzleFlashRendererDuration;
        if (muzzleFlashRenderer != null)
        {
            muzzleFlashRenderer.enabled = true;
        }
        if (rifleFireAudioSource != null && rifleFireClip != null)
        {
            rifleFireAudioSource.PlayOneShot(rifleFireClip);
        }
        if (targetFeedback != null)
        {
            targetFeedback.PlayShot(simulation.lastRings, simulation.lastWasHit);
        }
    }

    Transform FindChildRecursive(Transform root, string childName)
    {
        if (root.name == childName) return root;
        for (int i = 0; i < root.childCount; i++)
        {
            Transform child = FindChildRecursive(root.GetChild(i), childName);
            if (child != null) return child;
        }
        return null;
    }
}
