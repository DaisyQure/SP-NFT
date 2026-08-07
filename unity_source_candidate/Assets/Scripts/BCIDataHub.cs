using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Serialization;

/// <summary>
/// BCI 反馈数据中心:单例 + 跨场景持久化。
/// MATLAB 端可能发送任意 type 的反馈值,Hub 用字典存储,
/// 已知字段(attention/relaxation/simulationIntensity)做强类型映射方便游戏脚本读取。
/// </summary>
public class BCIDataHub : MonoBehaviour
{
    public static BCIDataHub Instance { get; private set; }

    [Header("Known Feedback Values (Runtime Read-only)")]
    [Range(0, 1)] public float attention = 0.5f;
    [Range(0, 1)] public float relaxation = 0.5f;
    [FormerlySerializedAs("motorIntensity")]
    [Range(0, 1)] public float simulationIntensity = 0.5f;

    [Header("Metadata")]
    public string currentScheme = "";
    public int lastSeq = -1;
    public double lastTs = 0;
    public int receivedCount = 0;

    [Header("Current A-B-A-B Phase (from MATLAB)")]
    public PhaseInfo currentPhase = new PhaseInfo();

    [Header("Feedback Modality (from MATLAB, Runtime-switchable)")]
    public Modality currentModality = Modality.Both;

    [Header("Current Monitoring Target (from MATLAB)")]
    public MonitorTarget currentMonitorTarget = MonitorTarget.Attention;

    [Header("Session gate")]
    public bool waitingForFeedbackStart = false;
    public bool hasReceivedFirstPhase = false;
    public string armedSceneName = "";

    public bool HasFeedbackStarted => hasReceivedFirstPhase;
    public bool IsPhaseBActive => hasReceivedFirstPhase && currentPhase != null && currentPhase.label == "B";
    public bool IsPhaseAActive => hasReceivedFirstPhase && currentPhase != null && currentPhase.label == "A";

    /// <summary>每次 MATLAB 下发 type=phase 消息时触发。订阅者: PhaseController, 场景 UI 等</summary>
    public event System.Action<PhaseInfo> OnPhaseChanged;

    /// <summary>type=modality 时触发。订阅者: 各 audio/visual 组件按通道自动启停</summary>
    public event System.Action<Modality> OnModalityChanged;

    /// <summary>type=monitor_target 时触发 (仅 scheme=monitor 场景关心)</summary>
    public event System.Action<MonitorTarget> OnMonitorTargetChanged;

    /// <summary>MATLAB 下发 type=session_stop 时触发。订阅者: PhaseController 等</summary>
    public event System.Action<string> OnSessionStop;

    /// <summary>当当前 scheme 发生变化时触发。订阅者: 运行时场景路由等</summary>
    public event System.Action<string> OnSchemeChanged;

    /// <summary>Unity 进入待命 / 收到首个 phase / session_stop 重置时触发。</summary>
    public event System.Action OnFeedbackGateChanged;

    private Dictionary<string, float> values = new Dictionary<string, float>();

    void Awake()
    {
        if (Instance != null && Instance != this) { Destroy(gameObject); return; }
        Instance = this;
        DontDestroyOnLoad(gameObject);

        Application.runInBackground = true;
    }

    public void ArmForScene(string sceneName)
    {
        armedSceneName = sceneName;
        waitingForFeedbackStart = true;
        hasReceivedFirstPhase = false;

        currentScheme = "";
        currentPhase = new PhaseInfo();
        currentModality = Modality.Both;
        currentMonitorTarget = MonitorTarget.Attention;
        attention = 0.5f;
        relaxation = 0.5f;
        simulationIntensity = 0.5f;
        lastSeq = -1;
        lastTs = 0;
        receivedCount = 0;
        values.Clear();

        NotifyFeedbackGateChanged();
    }

    public void UpdateFromMessage(FeedbackMsg msg)
    {
        // --- phase 控制消息: 不进 values 字典, 直接触发事件 ---
        if (msg.type == "phase")
        {
            bool schemeChanged = currentScheme != msg.scheme;
            HandlePhaseMessage(msg);
            currentScheme = msg.scheme;
            if (schemeChanged)
            {
                NotifySchemeChanged(msg.scheme);
            }
            lastSeq = msg.seq;
            lastTs = msg.ts;
            receivedCount++;
            return;
        }

        // --- session_stop: MATLAB 通知 session 已结束, Unity 立即回待机 ---
        if (msg.type == "session_stop")
        {
            HandleSessionStop(msg);
            lastSeq = msg.seq;
            lastTs = msg.ts;
            receivedCount++;
            return;
        }

        // --- modality: 通道切换 (Visual/Auditory/Both) ---
        if (msg.type == "modality")
        {
            HandleModality(msg);
            lastSeq = msg.seq;
            lastTs = msg.ts;
            receivedCount++;
            return;
        }

        // --- monitor_target: monitor 模式下当前关注目标 ---
        if (msg.type == "monitor_target")
        {
            HandleMonitorTarget(msg);
            lastSeq = msg.seq;
            lastTs = msg.ts;
            receivedCount++;
            return;
        }

        float v = Mathf.Clamp01(msg.value);
        values[msg.type] = v;

        switch (msg.type)
        {
            case "attention":
                attention = v;
                break;
            case "relaxation":
                relaxation = v;
                break;
            case "simulation_intensity":
            case "motor_intensity":
                simulationIntensity = v;
                break;
        }

        currentScheme = msg.scheme;
        lastSeq = msg.seq;
        lastTs = msg.ts;
        receivedCount++;
        if (!string.IsNullOrEmpty(msg.scheme))
        {
            NotifySchemeChanged(msg.scheme);
        }
    }

    void HandlePhaseMessage(FeedbackMsg msg)
    {
        bool gateChanged = waitingForFeedbackStart || !hasReceivedFirstPhase;
        waitingForFeedbackStart = false;
        hasReceivedFirstPhase = true;

        // value=0 → A, value=1 → B; info 格式: "<trial_idx>|<duration_sec>|<instruction_text>"
        var info = new PhaseInfo
        {
            label = (Mathf.RoundToInt(msg.value) == 0) ? "A" : "B",
            trialIdx = 0,
            durationSec = 0f,
            instruction = ""
        };

        if (!string.IsNullOrEmpty(msg.info))
        {
            string[] parts = msg.info.Split('|');
            if (parts.Length >= 1) int.TryParse(parts[0], out info.trialIdx);
            if (parts.Length >= 2) float.TryParse(parts[1], out info.durationSec);
            if (parts.Length >= 3) info.instruction = DecodePhaseInstruction(parts[2]);
        }

        info.instruction = SanitizePhaseInstruction(msg.scheme, info.label, info.instruction);

        currentPhase = info;
        if (gateChanged) NotifyFeedbackGateChanged();
        try { OnPhaseChanged?.Invoke(info); }
        catch (System.Exception e) { Debug.LogError($"[Hub] OnPhaseChanged subscriber error: {e.Message}"); }
    }

    string SanitizePhaseInstruction(string scheme, string phaseLabel, string instruction)
    {
        if (!string.IsNullOrEmpty(instruction) && instruction.IndexOf('�') < 0)
            return instruction;

        string fallback = GetPhaseInstructionFallback(scheme, phaseLabel);
        if (!string.IsNullOrEmpty(fallback))
        {
            Debug.LogWarning($"[Hub] Phase instruction was empty or invalid; using the built-in English fallback. scheme={scheme}, phase={phaseLabel}, original='{instruction}'");
            return fallback;
        }

        return instruction;
    }

    string DecodePhaseInstruction(string rawInstruction)
    {
        if (string.IsNullOrEmpty(rawInstruction))
            return rawInstruction;

        if (!rawInstruction.StartsWith("HEX:"))
            return rawInstruction;

        string hex = rawInstruction.Substring(4);
        if (hex.Length == 0 || (hex.Length % 2) != 0)
            return rawInstruction;

        try
        {
            byte[] bytes = new byte[hex.Length / 2];
            for (int i = 0; i < bytes.Length; i++)
                bytes[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);

            return System.Text.Encoding.UTF8.GetString(bytes);
        }
        catch (System.Exception e)
        {
            Debug.LogWarning($"[Hub] Failed to decode HEX phase instruction: {e.Message}");
            return rawInstruction;
        }
    }

    string GetPhaseInstructionFallback(string scheme, string phaseLabel)
    {
        if (phaseLabel == "A")
        {
            switch (scheme)
            {
                case "monitor":
                    return "Rest and relax while keeping your body still.";
                case "relax":
                case "attention":
                case "simulation":
                default:
                    return "Remain still, fixate on the cross, and breathe naturally.";
            }
        }

        switch (scheme)
        {
            case "relax":
                return "Breathe slowly and deeply, and gradually relax.";
            case "attention":
                return "Focus your attention and maintain concentration on the target.";
            case "simulation":
                return "Regulate your state according to the prompt.";
            case "monitor":
                return "Adjust your state according to the auditory cues.";
            default:
                return "Regulate your state according to the prompt.";
        }
    }

    void HandleSessionStop(FeedbackMsg msg)
    {
        // 清状态
        armedSceneName = "";
        waitingForFeedbackStart = false;
        hasReceivedFirstPhase = false;
        currentScheme = "";
        currentPhase = new PhaseInfo();
        currentModality = Modality.Both;
        currentMonitorTarget = MonitorTarget.Attention;
        attention = 0.5f;
        relaxation = 0.5f;
        simulationIntensity = 0.5f;
        values.Clear();

        NotifyFeedbackGateChanged();

        string reason = string.IsNullOrEmpty(msg.info) ? "matlab" : msg.info;
        try { OnSessionStop?.Invoke(reason); }
        catch (System.Exception e) { Debug.LogError($"[Hub] OnSessionStop subscriber error: {e.Message}"); }
    }

    void HandleModality(FeedbackMsg msg)
    {
        // value: 0=Visual 1=Auditory 2=Both
        int code = Mathf.RoundToInt(msg.value);
        Modality m;
        switch (code)
        {
            case 0:  m = Modality.Visual; break;
            case 1:  m = Modality.Auditory; break;
            default: m = Modality.Both; break;
        }
        if (m == currentModality) return;
        currentModality = m;
        try { OnModalityChanged?.Invoke(m); }
        catch (System.Exception e) { Debug.LogError($"[Hub] OnModalityChanged subscriber error: {e.Message}"); }
    }

    void HandleMonitorTarget(FeedbackMsg msg)
    {
        int code = Mathf.RoundToInt(msg.value);
        MonitorTarget t;
        switch (code)
        {
            case 1:  t = MonitorTarget.Relaxation; break;
            case 2:  t = MonitorTarget.Simulation; break;
            default: t = MonitorTarget.Attention; break;
        }
        if (t == currentMonitorTarget) return;
        currentMonitorTarget = t;
        try { OnMonitorTargetChanged?.Invoke(t); }
        catch (System.Exception e) { Debug.LogError($"[Hub] OnMonitorTargetChanged subscriber error: {e.Message}"); }
    }

    void NotifyFeedbackGateChanged()
    {
        try { OnFeedbackGateChanged?.Invoke(); }
        catch (System.Exception e) { Debug.LogError($"[Hub] OnFeedbackGateChanged subscriber error: {e.Message}"); }
    }

    void NotifySchemeChanged(string scheme)
    {
        try { OnSchemeChanged?.Invoke(scheme); }
        catch (System.Exception e) { Debug.LogError($"[Hub] OnSchemeChanged subscriber error: {e.Message}"); }
    }

    public float GetValue(string type)
    {
        return values.TryGetValue(type, out float v) ? v : 0.5f;
    }
}

[System.Serializable]
public class PhaseInfo
{
    public string label = "";           // "A" or "B"
    public int trialIdx = 0;
    public float durationSec = 0f;
    public string instruction = "";
}

public enum Modality { Visual = 0, Auditory = 1, Both = 2 }
public enum MonitorTarget { Attention = 0, Relaxation = 1, Simulation = 2 }

[System.Serializable]
public class FeedbackMsg
{
    public int seq;
    public double ts;
    public string type;
    public float value;
    public string scheme;
    public string info;

    [System.NonSerialized] public double tsUnityRecv;
}
