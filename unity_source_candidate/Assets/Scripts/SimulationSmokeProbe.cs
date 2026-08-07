using System;
using UnityEngine;
using UnityEngine.SceneManagement;

public sealed class SimulationSmokeProbe : MonoBehaviour
{
    static SimulationSmokeProbe instance;

    bool enabledForSmoke;
    bool subscribed;
    bool initialized;
    SimulationGameManager simulation;
    Simulation3DView view;
    Simulation3DTargetFeedback feedback;
    Vector3 initialRigPosition;
    Quaternion initialRigRotation;
    int initialImpactCount;
    float maxIntensity;
    float maxPositionDelta;
    float maxRotationDelta;

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    static void Bootstrap()
    {
        if (instance != null) return;
        GameObject go = new GameObject("SimulationSmokeProbe");
        instance = go.AddComponent<SimulationSmokeProbe>();
        DontDestroyOnLoad(go);
    }

    void Awake()
    {
        if (instance != null && instance != this)
        {
            Destroy(gameObject);
            return;
        }
        instance = this;
        DontDestroyOnLoad(gameObject);
        enabledForSmoke = HasArgument("-spnftSmokeProbe");
        if (!enabledForSmoke) return;
        SceneManager.sceneLoaded += OnSceneLoaded;
        TrySubscribe();
    }

    void OnDestroy()
    {
        SceneManager.sceneLoaded -= OnSceneLoaded;
        if (subscribed && BCIDataHub.Instance != null)
            BCIDataHub.Instance.OnSessionStop -= OnSessionStop;
    }

    void OnSceneLoaded(Scene scene, LoadSceneMode mode)
    {
        if (!enabledForSmoke) return;
        TrySubscribe();
        if (scene.name == "Game_Simulation3D") TryInitialize();
    }

    void Update()
    {
        if (!enabledForSmoke) return;
        TrySubscribe();
        if (!initialized) TryInitialize();
        if (!initialized || simulation == null || view == null || view.rifleRigRoot == null) return;

        maxIntensity = Mathf.Max(maxIntensity, simulation.currentIntensity);
        maxPositionDelta = Mathf.Max(maxPositionDelta,
            Vector3.Distance(initialRigPosition, view.rifleRigRoot.localPosition));
        maxRotationDelta = Mathf.Max(maxRotationDelta,
            Quaternion.Angle(initialRigRotation, view.rifleRigRoot.localRotation));
    }

    void TryInitialize()
    {
        simulation = FindObjectOfType<SimulationGameManager>();
        view = FindObjectOfType<Simulation3DView>();
        feedback = FindObjectOfType<Simulation3DTargetFeedback>();
        if (simulation == null || view == null || feedback == null || view.rifleRigRoot == null || feedback.impactRoot == null)
            return;

        simulation.threshold = 0.25f;
        simulation.holdTimeSec = 0.5f;
        simulation.intertrialIntervalSec = 0.4f;
        initialRigPosition = view.rifleRigRoot.localPosition;
        initialRigRotation = view.rifleRigRoot.localRotation;
        initialImpactCount = feedback.impactRoot.childCount;
        initialized = true;

        bool interfacesOk = view.rifleRigRoot.name == "Rifle_WeaponObject"
            && view.rifleWeapon != null && view.rifleWeapon.name == "Weapon"
            && view.rifleAimPoint != null && view.rifleAimPoint.name == "AimPoint"
            && view.rifleFirePoint != null && view.rifleFirePoint.name == "FirePoint"
            && view.rifleSwayPivot != null && view.rifleSwayPivot.name == "SwayPivot"
            && view.targetAimPoint != null && view.targetAimPoint.name == "TargetAimPoint";
        Debug.Log($"[SimulationSmokeProbe] INTERFACES {(interfacesOk ? "PASS" : "FAIL")}");
        Debug.Log("[SimulationSmokeProbe] Test-only threshold=0.25 hold=0.5s");
    }

    void TrySubscribe()
    {
        if (subscribed || BCIDataHub.Instance == null) return;
        BCIDataHub.Instance.OnSessionStop += OnSessionStop;
        subscribed = true;
    }

    void OnSessionStop(string reason)
    {
        int impactDelta = feedback != null && feedback.impactRoot != null
            ? feedback.impactRoot.childCount - initialImpactCount
            : 0;
        bool feedbackPass = maxIntensity > 0.05f;
        bool motionPass = maxPositionDelta > 0.001f || maxRotationDelta > 0.1f;
        bool targetPass = impactDelta > 0;
        Debug.Log($"[SimulationSmokeProbe] FEEDBACK {(feedbackPass ? "PASS" : "FAIL")} maxIntensity={maxIntensity:F3}");
        Debug.Log($"[SimulationSmokeProbe] MOTION {(motionPass ? "PASS" : "FAIL")} positionDelta={maxPositionDelta:F4} rotationDelta={maxRotationDelta:F3}");
        Debug.Log($"[SimulationSmokeProbe] TARGET {(targetPass ? "PASS" : "FAIL")} impactDelta={impactDelta}");
        Debug.Log($"[SimulationSmokeProbe] RESULT {(feedbackPass && motionPass && targetPass ? "PASS" : "FAIL")} reason={reason}");
    }

    static bool HasArgument(string expected)
    {
        foreach (string arg in Environment.GetCommandLineArgs())
        {
            if (string.Equals(arg, expected, StringComparison.OrdinalIgnoreCase)) return true;
        }
        return false;
    }
}
