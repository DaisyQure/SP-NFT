using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;

/// <summary>
/// Simulation 范式状态机 (Step S1)
///
/// 范式定义 (参照 simulation实现提示词.txt + NASA APPT / BioPhyS):
///   - 被试维持"最佳射击脑状态"
///   - simulation_intensity 高 → 虚拟手臂从下垂位抬起
///   - 状态稳定在Threshold之上 ≥ holdTimeSec → 自动击发
///   - 状态崩溃 → 手臂回落, 试次失败
///   - 每个 session 完成 trialCount 个试次, 课程化抬Threshold
///
/// 状态机:
///   IDLE → AIMING → READY_TO_FIRE → FIRED → RESET → AIMING ...
///   超时未到达 READY_TO_FIRE 也算 FIRED (失败击发) → RESET
///
/// 本脚本 Step S1 只实现核心状态机, 暂不挂任何 UI/动画。
/// 通过 Console 日志和 marker 通道即可验证时序。
/// </summary>
public class SimulationGameManager : MonoBehaviour
{
    public static SimulationGameManager Instance { get; private set; }

    public enum TrialState { Idle, Aiming, ReadyToFire, Fired, Reset }
    // DEV_PLAN 三 · 全局原则: modality 由 MATLAB 运行时下发, 不在 Inspector 配
    // 旧 enum Modality 已移除, 改用 BCIDataHub.Modality (全局 enum)

    [Header("Trial Parameters")]
    [Tooltip("Total number of trials")]
    public int trialCount = 20;
    [Tooltip("Maximum aiming time; timeout counts as a failed shot")]
    public float maxAimTimeSec = 20f;
    [Tooltip("Time above threshold required to trigger automatic fire")]
    public float holdTimeSec = 1.5f;
    [Tooltip("Inter-trial interval")]
    public float intertrialIntervalSec = 2.5f;

    [Header("Threshold")]
    [Tooltip("Current automatic-fire threshold (adapted by ThresholdAdapter)")]
    [Range(0f, 1f)] public float threshold = 0.65f;

    [Header("Runtime State (Read-only)")]
    public TrialState state = TrialState.Idle;
    public int currentTrial = 0;
    public int hitsCount = 0;
    public int totalScore = 0;
    public float trialTimeElapsed = 0f;
    public float aboveThresholdDuration = 0f;
    public float currentIntensity = 0f;
    public bool sessionFinished = false;

    [Header("Shot Result (Read-only, Used by UI)")]
    public int lastRings = 0;          // 上一次击发的环数 (0=miss, 5-10=hit)
    public bool lastWasHit = false;    // 上一次是否命中
    public float lastStability = 0f;   // 上一次 hold 窗口稳定性 (0~1, 越大越稳)
    public float lastPeak = 0f;        // 上一次 hold 窗口 intensity 峰值
    public float lastMean = 0f;        // 上一次 hold 窗口 intensity 均值
    public float lastSpeedFactor = 0f; // 上一次达标速度因子 (0~1, 越快越大)

    [Header("Smoothing")]
    [Tooltip("EMA smoothing factor for intensity (0-1; larger values respond faster)")]
    [Range(0f, 1f)] public float smoothingAlpha = 0.2f;

    private float smoothedIntensity = 0f;
    private float resetTimer = 0f;
    private List<float> holdSamples = new List<float>(128);  // hold 窗口期间的 intensity 采样

    void Awake()
    {
        if (Instance != null && Instance != this) { Destroy(gameObject); return; }
        Instance = this;
    }

    void Start()
    {
        TcpFeedbackClient.Instance?.SendMarker("session_start", trialCount, "simulation");
        Debug.Log($"[Simulation] Session started: {trialCount} trials, threshold={threshold:F2}");
        // A-B-A-B 范式: 试次不再在 Start 自动开始, 改由 PhaseController 在 phase=B 时调
        // BeginNextTrial();   // 已禁用, 见 BeginTrialFromExternal
    }

    void Update()
    {
        if (sessionFinished) return;

        var hub = BCIDataHub.Instance;
        bool gameplayActive = hub != null && hub.IsPhaseBActive;

        // ----- 读取并平滑 intensity -----
        float rawIntensity = gameplayActive && hub != null
            ? hub.simulationIntensity
            : 0f;
        smoothedIntensity = smoothingAlpha * rawIntensity + (1f - smoothingAlpha) * smoothedIntensity;
        currentIntensity = smoothedIntensity;

        if (!gameplayActive)
        {
            aboveThresholdDuration = 0f;
            holdSamples.Clear();
            return;
        }

        // ----- 状态机推进 -----
        switch (state)
        {
            case TrialState.Idle:
                // 初始态, BeginNextTrial 会推到 Aiming
                break;

            case TrialState.Aiming:
                trialTimeElapsed += Time.deltaTime;
                if (smoothedIntensity >= threshold)
                {
                    aboveThresholdDuration += Time.deltaTime;
                    holdSamples.Add(smoothedIntensity);
                    if (aboveThresholdDuration >= holdTimeSec)
                    {
                        EnterReadyToFire();
                    }
                }
                else
                {
                    if (aboveThresholdDuration > 0f)
                    {
                        TcpFeedbackClient.Instance?.SendMarker("state_dropped", smoothedIntensity, "simulation");
                        Debug.Log($"[Trial {currentTrial}] State dropped below threshold, intensity={smoothedIntensity:F2}");
                    }
                    aboveThresholdDuration = 0f;
                    holdSamples.Clear();
                }

                if (trialTimeElapsed >= maxAimTimeSec)
                {
                    Debug.Log($"[Trial {currentTrial}] Timed out; trial failed");
                    EnterFired(false, 0);
                }
                break;

            case TrialState.ReadyToFire:
                // 通常立刻进入 Fired (在 EnterReadyToFire 里直接调度)
                break;

            case TrialState.Fired:
                resetTimer += Time.deltaTime;
                if (resetTimer >= intertrialIntervalSec)
                {
                    state = TrialState.Reset;
                    OnTrialFinished();
                }
                break;

            case TrialState.Reset:
                // A-B-A-B 范式下: 一次试次结束后回到 Idle 等待 PhaseController 下次 B 信号,
                // 不再自动 BeginNextTrial
                state = TrialState.Idle;
                break;
        }
    }

    /// <summary>由 PhaseController 在进入 B 阶段时调用; 若内部已 Idle 则启动新试次, 否则忽略</summary>
    public void BeginTrialFromExternal()
    {
        if (sessionFinished) return;
        if (state == TrialState.Idle)
        {
            BeginNextTrial();
        }
        else
        {
            ForceEndCurrentTrial();
        }
    }

    public void ForceEndCurrentTrial()
    {
        if (sessionFinished) return;
        if (state == TrialState.Aiming || state == TrialState.ReadyToFire)
        {
            EnterFired(false, 0);
            state = TrialState.Idle;
            resetTimer = 0f;
        }
        else if (state == TrialState.Fired || state == TrialState.Reset)
        {
            state = TrialState.Idle;
            resetTimer = 0f;
        }
    }

    void BeginNextTrial()
    {
        currentTrial++;
        state = TrialState.Aiming;
        trialTimeElapsed = 0f;
        aboveThresholdDuration = 0f;
        resetTimer = 0f;
        TcpFeedbackClient.Instance?.SendMarker("trial_start", currentTrial, "simulation");
        TcpFeedbackClient.Instance?.SendMarker("aim_start", threshold, "simulation");
        Debug.Log($"[Trial {currentTrial}/{trialCount}] Aiming started, threshold={threshold:F2}");
    }

    void EnterReadyToFire()
    {
        state = TrialState.ReadyToFire;
        TcpFeedbackClient.Instance?.SendMarker("state_above_threshold", smoothedIntensity, "simulation");
        Debug.Log($"[Trial {currentTrial}] Threshold maintained for >= {holdTimeSec}s; preparing to fire");

        // ---- 击发评分: peak + stability + 速度 三因子 ----
        // peak: hold 窗口最高 intensity, 衡量"瞄准上限"
        // stability: 1 - 5*std (只统计后半段, 避开上升趋势对 std 的污染)
        // speedFactor: trial 总用时越短越好
        float mean = 0f, variance = 0f, peak = 0f;
        int n = holdSamples.Count;
        int startIdx = n / 2;                          // 只用后半段
        int validN = Mathf.Max(n - startIdx, 1);
        if (n > 0)
        {
            for (int i = 0; i < n; i++) { if (holdSamples[i] > peak) peak = holdSamples[i]; }  // peak 用全段
            for (int i = startIdx; i < n; i++) mean += holdSamples[i];
            mean /= validN;
            for (int i = startIdx; i < n; i++) variance += (holdSamples[i] - mean) * (holdSamples[i] - mean);
            variance /= validN;
        }
        else
        {
            mean = peak = smoothedIntensity;
        }
        float std = Mathf.Sqrt(variance);

        // 非线性映射拉开区分度: peak 越高得分越陡上升
        float peakRaw = Mathf.Clamp01((peak - threshold) / Mathf.Max(1f - threshold, 0.01f));
        float peakScore = Mathf.Pow(peakRaw, 1.6f);                                              // ^1.6 让中低段更低
        float stability = Mathf.Clamp01(1f - std * 5f);
        float speedFactor = Mathf.Clamp01(1f - trialTimeElapsed / Mathf.Max(maxAimTimeSec, 1f));

        lastPeak = peak;
        lastMean = mean;
        lastStability = stability;
        lastSpeedFactor = speedFactor;

        // 3 保底 + peak 0-5 + stability 0-1 + speed 0-1 = 3-10 环 (clamp 到 5-10)
        // peak 占绝对主导, 让 5/6/7 环在低 peak 时真正出现
        float hitScore = 3f + peakScore * 5f + stability * 1f + speedFactor * 1f;
        int rings = Mathf.Clamp(Mathf.RoundToInt(hitScore), 5, 10);
        EnterFired(true, rings);
    }

    void EnterFired(bool isHit, int rings)
    {
        state = TrialState.Fired;
        resetTimer = 0f;
        lastRings = rings;
        lastWasHit = isHit;

        if (isHit)
        {
            hitsCount++;
            totalScore += rings;
            TcpFeedbackClient.Instance?.SendMarker("auto_fire", rings, "simulation");
            Debug.Log($"[Trial {currentTrial}] Hit: {rings} rings | peak={lastPeak:F2} stability={lastStability:F2} speed={lastSpeedFactor:F2} | total score={totalScore}");
        }
        else
        {
            TcpFeedbackClient.Instance?.SendMarker("auto_fire", 0, "simulation");
            Debug.Log($"[Trial {currentTrial}] Shot missed: 0 rings");
        }
        TcpFeedbackClient.Instance?.SendMarker("trial_end", isHit ? 1 : 0, "simulation");
        holdSamples.Clear();
    }

    void OnTrialFinished()
    {
        // 通知 ThresholdAdapter (Step S4 会实现) 评估命中率
        var adapter = GetComponent<ThresholdAdapter>();
        if (adapter != null)
        {
            adapter.OnTrialFinished(currentTrial, hitsCount);
        }
    }

    void EndSession()
    {
        sessionFinished = true;
        state = TrialState.Idle;
        float hitRate = (currentTrial > 0) ? (float)hitsCount / currentTrial : 0f;
        Debug.Log($"[Simulation] Session ended: trials={currentTrial}, hits={hitsCount}, hit rate={hitRate:F2}, total score={totalScore}");
        TcpFeedbackClient.Instance?.SendMarker("session_end", totalScore, "simulation");
    }

    public void ReturnToMenu()
    {
        Time.timeScale = 1f;
        string sceneToUnload = gameObject.scene.name;
        TcpFeedbackClient.Instance?.SendMarker("menu_return", totalScore, sceneToUnload);
        StartCoroutine(LoadMenuAndUnload(sceneToUnload));
    }

    private IEnumerator LoadMenuAndUnload(string sceneToUnload)
    {
        Scene menuScene = SceneManager.GetSceneByName("MainMenu");
        if (!menuScene.isLoaded)
        {
            AsyncOperation loadOp = SceneManager.LoadSceneAsync("MainMenu", LoadSceneMode.Additive);
            while (!loadOp.isDone) yield return null;
        }
        AsyncOperation unloadOp = SceneManager.UnloadSceneAsync(sceneToUnload);
        while (unloadOp != null && !unloadOp.isDone) yield return null;
    }
}
