using System.Collections;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;
using TMPro;

/// <summary>
/// A-B-A-B 范式控制器(被试端单点接管):
///   - 订阅 BCIDataHub.OnPhaseChanged
///   - A 阶段: 全屏 overlay (黑半透 + 十字 + 指导语 + Trial X/N), Time.timeScale=0 暂停游戏
///   - B 阶段: 隐藏 overlay, Time.timeScale=1, 若是 simulation 场景则触发 Simulation 试次
///   - Game_Monitor 场景:overlay 显示但不切 timeScale (无可视游戏)
///
/// 自挂载: 通过 RuntimeInitializeOnLoadMethod 在游戏启动时自动创建,
///   不需要在 _Bootstrap.unity 序列化里手动加 Component。
/// </summary>
public class PhaseController : MonoBehaviour
{
    public static PhaseController Instance { get; private set; }

    [Header("Current Phase (Runtime Read-only)")]
    public string currentLabel = "";
    public int currentTrialIdx = 0;
    public float currentDurationSec = 0f;

    private Canvas overlayCanvas;
    private GameObject overlayRoot;
    private TMP_Text instructionText;
    private TMP_Text trialText;
    private Image crosshairImg;

    private bool wasTimeScalePaused = false;
    private bool sceneEventsRegistered = false;

    private static readonly string[] SimulationSceneNames = {
        "Game_Shooter",
        MainMenuController.SimulationSceneName
    };

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    private static void AutoBootstrap()
    {
        if (Instance != null) return;
        var go = new GameObject("PhaseController");
        go.AddComponent<PhaseController>();
    }

    void Awake()
    {
        if (Instance != null && Instance != this) { Destroy(gameObject); return; }
        Instance = this;
        DontDestroyOnLoad(gameObject);

        RegisterSceneEvents();
        TrySubscribe();
    }

    void Start()
    {
        TrySubscribe();
        ApplyGateState();
    }

    void TrySubscribe()
    {
        var hub = BCIDataHub.Instance;
        if (hub == null) return;
        hub.OnPhaseChanged -= HandlePhaseChanged;
        hub.OnPhaseChanged += HandlePhaseChanged;
        hub.OnSessionStop -= HandleSessionStop;
        hub.OnSessionStop += HandleSessionStop;
        hub.OnFeedbackGateChanged -= HandleFeedbackGateChanged;
        hub.OnFeedbackGateChanged += HandleFeedbackGateChanged;
    }

    void OnDestroy()
    {
        var hub = BCIDataHub.Instance;
        if (hub != null)
        {
            hub.OnPhaseChanged -= HandlePhaseChanged;
            hub.OnSessionStop -= HandleSessionStop;
            hub.OnFeedbackGateChanged -= HandleFeedbackGateChanged;
        }
        UnregisterSceneEvents();
        if (wasTimeScalePaused) Time.timeScale = 1f;
    }

    void HandleFeedbackGateChanged()
    {
        ApplyGateState();
    }

    void HandlePhaseChanged(PhaseInfo info)
    {
        currentLabel = info.label;
        currentTrialIdx = info.trialIdx;
        currentDurationSec = info.durationSec;

        bool isA = info.label == "A";
        bool inMonitorScene = IsMonitorSceneActive();

        EnsureOverlay();

        if (isA)
        {
            if (IsSimulationSceneActive())
            {
                var sim = SimulationGameManager.Instance;
                if (sim != null) sim.ForceEndCurrentTrial();
            }

            ShowOverlay(info);
            if (!inMonitorScene)
            {
                Time.timeScale = 0f;
                wasTimeScalePaused = true;
            }
        }
        else
        {
            HideOverlay();
            if (wasTimeScalePaused)
            {
                Time.timeScale = 1f;
                wasTimeScalePaused = false;
            }
            if (IsSimulationSceneActive())
            {
                var sim = SimulationGameManager.Instance;
                if (sim != null) sim.BeginTrialFromExternal();
            }
        }

        TcpFeedbackClient.Instance?.SendMarker("phase_ack", isA ? 0f : 1f, info.label);
    }

    void HandleSessionStop(string reason)
    {
        Debug.Log($"[PhaseController] Received session_stop, reason={reason}");
        currentLabel = "";
        currentTrialIdx = 0;
        currentDurationSec = 0f;

        Time.timeScale = 1f;
        wasTimeScalePaused = false;
        HideOverlay();

        TcpFeedbackClient.Instance?.SendMarker("session_stop_ack", 0f, reason);

        StartCoroutine(ReturnToMainMenuRoutine());
    }

    private static readonly string[] GameSceneNames = {
        "Game_Attention", "Game_Shooter", MainMenuController.SimulationSceneName, "Game_Relax", "Game_Monitor"
    };

    IEnumerator ReturnToMainMenuRoutine()
    {
        var toUnload = new System.Collections.Generic.List<string>();
        for (int i = 0; i < SceneManager.sceneCount; i++)
        {
            var s = SceneManager.GetSceneAt(i);
            if (!s.isLoaded) continue;
            foreach (var n in GameSceneNames)
            {
                if (s.name == n) { toUnload.Add(s.name); break; }
            }
        }

        var menu = SceneManager.GetSceneByName("MainMenu");
        if (!menu.isLoaded)
        {
            var loadOp = SceneManager.LoadSceneAsync("MainMenu", LoadSceneMode.Additive);
            while (loadOp != null && !loadOp.isDone) yield return null;
        }

        foreach (var name in toUnload)
        {
            var unloadOp = SceneManager.UnloadSceneAsync(name);
            while (unloadOp != null && !unloadOp.isDone) yield return null;
        }
    }

    void RegisterSceneEvents()
    {
        if (sceneEventsRegistered) return;
        SceneManager.sceneLoaded += OnSceneLoaded;
        SceneManager.sceneUnloaded += OnSceneUnloaded;
        sceneEventsRegistered = true;
    }

    void UnregisterSceneEvents()
    {
        if (!sceneEventsRegistered) return;
        SceneManager.sceneLoaded -= OnSceneLoaded;
        SceneManager.sceneUnloaded -= OnSceneUnloaded;
        sceneEventsRegistered = false;
    }

    void OnSceneLoaded(Scene scene, LoadSceneMode mode)
    {
        TrySubscribe();
        ApplyGateState();
    }

    void OnSceneUnloaded(Scene scene)
    {
        ApplyGateState();
    }

    void ApplyGateState()
    {
        var hub = BCIDataHub.Instance;
        if (hub == null)
            return;

        EnsureOverlay();

        if (!IsAnyGameSceneLoaded())
        {
            HideOverlay();
            if (wasTimeScalePaused)
            {
                Time.timeScale = 1f;
                wasTimeScalePaused = false;
            }
            return;
        }

        bool inMonitorScene = IsMonitorSceneActive();
        if (!hub.HasFeedbackStarted)
        {
            ShowWaitingOverlay();
            if (!inMonitorScene)
            {
                Time.timeScale = 0f;
                wasTimeScalePaused = true;
            }
            return;
        }

        if (hub.currentPhase != null && hub.currentPhase.label == "A")
        {
            ShowOverlay(hub.currentPhase);
            if (!inMonitorScene)
            {
                Time.timeScale = 0f;
                wasTimeScalePaused = true;
            }
            return;
        }

        HideOverlay();
        if (wasTimeScalePaused)
        {
            Time.timeScale = 1f;
            wasTimeScalePaused = false;
        }
    }

    bool IsAnyGameSceneLoaded()
    {
        for (int i = 0; i < SceneManager.sceneCount; i++)
        {
            var scene = SceneManager.GetSceneAt(i);
            if (!scene.isLoaded) continue;
            foreach (var name in GameSceneNames)
            {
                if (scene.name == name) return true;
            }
        }
        return false;
    }

    bool IsSceneLoaded(string sceneName)
    {
        var scene = SceneManager.GetSceneByName(sceneName);
        return scene.IsValid() && scene.isLoaded;
    }

    bool IsSimulationSceneActive()
    {
        foreach (var sceneName in SimulationSceneNames)
        {
            if (IsSceneLoaded(sceneName)) return true;
        }
        return false;
    }

    bool IsMonitorSceneActive()
    {
        return IsSceneLoaded("Game_Monitor");
    }

    void EnsureOverlay()
    {
        if (overlayRoot != null) return;

        var canvasGo = new GameObject("PhaseOverlayCanvas");
        canvasGo.transform.SetParent(transform, false);
        overlayCanvas = canvasGo.AddComponent<Canvas>();
        overlayCanvas.renderMode = RenderMode.ScreenSpaceOverlay;
        overlayCanvas.sortingOrder = 32760;
        canvasGo.AddComponent<CanvasScaler>();
        canvasGo.AddComponent<GraphicRaycaster>();

        overlayRoot = new GameObject("Root");
        overlayRoot.transform.SetParent(canvasGo.transform, false);
        var bg = overlayRoot.AddComponent<Image>();
        bg.color = new Color(0f, 0f, 0f, 0.78f);
        var rt = bg.rectTransform;
        rt.anchorMin = Vector2.zero; rt.anchorMax = Vector2.one;
        rt.offsetMin = Vector2.zero; rt.offsetMax = Vector2.zero;

        var crossGo = new GameObject("Crosshair");
        crossGo.transform.SetParent(overlayRoot.transform, false);
        crosshairImg = crossGo.AddComponent<Image>();
        crosshairImg.color = new Color(1f, 1f, 1f, 0.9f);
        crosshairImg.sprite = MakeCrossSprite();
        var crt = crosshairImg.rectTransform;
        crt.anchorMin = new Vector2(0.5f, 0.5f);
        crt.anchorMax = new Vector2(0.5f, 0.5f);
        crt.sizeDelta = new Vector2(120f, 120f);
        crt.anchoredPosition = Vector2.zero;

        var instrGo = new GameObject("Instruction");
        instrGo.transform.SetParent(overlayRoot.transform, false);
        instructionText = instrGo.AddComponent<TextMeshProUGUI>();
        instructionText.text = "";
        instructionText.fontSize = 38;
        instructionText.alignment = TextAlignmentOptions.Center;
        instructionText.color = Color.white;
        var irt = instructionText.rectTransform;
        irt.anchorMin = new Vector2(0.1f, 0.18f);
        irt.anchorMax = new Vector2(0.9f, 0.32f);
        irt.offsetMin = Vector2.zero; irt.offsetMax = Vector2.zero;

        var trialGo = new GameObject("TrialLabel");
        trialGo.transform.SetParent(overlayRoot.transform, false);
        trialText = trialGo.AddComponent<TextMeshProUGUI>();
        trialText.text = "";
        trialText.fontSize = 22;
        trialText.alignment = TextAlignmentOptions.Center;
        trialText.color = new Color(0.7f, 0.85f, 1f, 0.8f);
        var trt = trialText.rectTransform;
        trt.anchorMin = new Vector2(0.1f, 0.78f);
        trt.anchorMax = new Vector2(0.9f, 0.88f);
        trt.offsetMin = Vector2.zero; trt.offsetMax = Vector2.zero;

        var preferredFont = TMP_Settings.defaultFontAsset;
        if (preferredFont != null)
        {
            instructionText.font = preferredFont;
            trialText.font = preferredFont;
        }

        overlayRoot.SetActive(false);
    }

    void ShowWaitingOverlay()
    {
        if (overlayRoot == null) return;
        overlayRoot.SetActive(true);
        if (instructionText != null) instructionText.text = "Waiting for MATLAB baseline acquisition to finish.";
        if (trialText != null) trialText.text = "STANDBY";
    }

    void ShowOverlay(PhaseInfo info)
    {
        if (overlayRoot == null) return;
        overlayRoot.SetActive(true);
        if (instructionText != null) instructionText.text = info.instruction;
        if (trialText != null)
            trialText.text = $"Trial {info.trialIdx}    Phase A ({info.durationSec:F0} s)";
    }

    void HideOverlay()
    {
        if (overlayRoot != null) overlayRoot.SetActive(false);
    }

    static Sprite MakeCrossSprite()
    {
        int sz = 64;
        var tex = new Texture2D(sz, sz, TextureFormat.RGBA32, false);
        tex.filterMode = FilterMode.Bilinear;
        var clear = new Color(0f, 0f, 0f, 0f);
        var white = new Color(1f, 1f, 1f, 1f);
        for (int x = 0; x < sz; x++)
            for (int y = 0; y < sz; y++)
                tex.SetPixel(x, y, clear);
        int mid = sz / 2;
        int thick = 4;
        for (int x = 6; x < sz - 6; x++)
            for (int dy = -thick / 2; dy < thick / 2; dy++)
                tex.SetPixel(x, mid + dy, white);
        for (int y = 6; y < sz - 6; y++)
            for (int dx = -thick / 2; dx < thick / 2; dx++)
                tex.SetPixel(mid + dx, y, white);
        tex.Apply();
        return Sprite.Create(tex, new Rect(0, 0, sz, sz), new Vector2(0.5f, 0.5f));
    }
}
