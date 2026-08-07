using System;
using System.Collections;
using UnityEngine;
using UnityEngine.SceneManagement;
#if UNITY_EDITOR
using UnityEditor;
#endif

public class SmokeAutoRunner : MonoBehaviour
{
    private static SmokeAutoRunner instance;

    private bool automationEnabled;
    private bool quitOnSessionStop;
    private bool loadTriggered;
    private string requestedMode = "attention";

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    private static void Bootstrap()
    {
        if (instance != null) return;
        var go = new GameObject("SmokeAutoRunner");
        instance = go.AddComponent<SmokeAutoRunner>();
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

        ParseCommandLine();
        SceneManager.sceneLoaded += OnSceneLoaded;
        TrySubscribe();
    }

    void OnDestroy()
    {
        SceneManager.sceneLoaded -= OnSceneLoaded;
        if (BCIDataHub.Instance != null)
        {
            BCIDataHub.Instance.OnSessionStop -= HandleSessionStop;
        }
    }

    void ParseCommandLine()
    {
        string[] args = Environment.GetCommandLineArgs();
        for (int i = 0; i < args.Length; i++)
        {
            string arg = args[i];
            if (arg == "-spnftAutoScene" && i + 1 < args.Length)
            {
                requestedMode = NormalizeMode(args[i + 1]);
                automationEnabled = true;
                i++;
                continue;
            }
            if (arg.StartsWith("-spnftAutoScene=", StringComparison.OrdinalIgnoreCase))
            {
                requestedMode = NormalizeMode(arg.Substring("-spnftAutoScene=".Length));
                automationEnabled = true;
                continue;
            }
            if (arg == "-spnftQuitOnSessionStop")
            {
                quitOnSessionStop = true;
                continue;
            }
        }

        if (automationEnabled && Application.isBatchMode)
        {
            quitOnSessionStop = true;
        }
    }

    void OnSceneLoaded(Scene scene, LoadSceneMode mode)
    {
        TrySubscribe();
        if (!automationEnabled || loadTriggered) return;
        if (scene.name == "MainMenu")
        {
            StartCoroutine(LoadRequestedSceneWhenReady());
        }
    }

    void TrySubscribe()
    {
        var hub = BCIDataHub.Instance;
        if (hub == null) return;
        hub.OnSessionStop -= HandleSessionStop;
        hub.OnSessionStop += HandleSessionStop;
    }

    IEnumerator LoadRequestedSceneWhenReady()
    {
        if (loadTriggered) yield break;
        loadTriggered = true;

        float deadline = Time.realtimeSinceStartup + 10f;
        while (BCIDataHub.Instance == null && Time.realtimeSinceStartup < deadline)
        {
            yield return null;
        }

        var plan = ResolvePlan(requestedMode);
        if (string.IsNullOrEmpty(plan.sceneName))
        {
            Debug.LogWarning($"[SmokeAuto] Unknown mode: {requestedMode}");
            yield break;
        }

        BCIDataHub.Instance?.ArmForScene(plan.sceneName);
        TcpFeedbackClient.Instance?.SendMarker(plan.menuEvent, 0f, plan.sceneName);

        AsyncOperation unloadOp = SceneManager.UnloadSceneAsync("MainMenu");
        while (unloadOp != null && !unloadOp.isDone)
        {
            yield return null;
        }

        AsyncOperation loadOp = SceneManager.LoadSceneAsync(plan.sceneName, LoadSceneMode.Additive);
        while (loadOp != null && !loadOp.isDone)
        {
            yield return null;
        }

        Debug.Log($"[SmokeAuto] Loaded {plan.sceneName} for mode {requestedMode}");
    }

    void HandleSessionStop(string reason)
    {
        if (!automationEnabled || !quitOnSessionStop) return;
        StartCoroutine(QuitSoon(reason));
    }

    IEnumerator QuitSoon(string reason)
    {
        Debug.Log($"[SmokeAuto] Session stopped, quitting soon. reason={reason}");
        yield return new WaitForSecondsRealtime(0.5f);
#if UNITY_EDITOR
        EditorApplication.isPlaying = false;
#else
        Application.Quit(0);
#endif
    }

    static string NormalizeMode(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return "attention";
        string s = raw.Trim().ToLowerInvariant();
        if (s == "shooter") return "simulation";
        return s;
    }

    static (string sceneName, string menuEvent) ResolvePlan(string mode)
    {
        switch (NormalizeMode(mode))
        {
            case "simulation":
                return (MainMenuController.SimulationSceneName, "menu_select_simulation");
            case "relax":
                return ("Game_Relax", "menu_select_relax");
            case "monitor":
                return ("Game_Monitor", "menu_select_monitor");
            default:
                return ("Game_Attention", "menu_select_attention");
        }
    }
}
