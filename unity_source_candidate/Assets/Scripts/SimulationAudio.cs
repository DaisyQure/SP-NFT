using UnityEngine;

/// <summary>
/// Simulation 范式听觉反馈 (SA-2).
///
/// 不依赖任何外部音频文件: 用 OnAudioFilterRead 直接合成正弦波 + 谐波 + 噪声.
///
/// 映射:
///   - 基础载波 sine, 频率 = lerp(220Hz, 660Hz, intensity)
///   - 低于阈值: 叠加少量粉噪声 ("模糊感")
///   - 达标击发: 触发 fanfare (C5 大三和弦 + 高八度), 0.6s 衰减
///   - 失败击发: 触发降调 (220→110Hz), 0.3s
///   - modality == Visual 时整个组件自动静音, 不参与
///
/// 挂载: 在 SimulationManager 同物体上, 与 SimulationGameManager / ThresholdAdapter 同级.
///       同物体必须有一个 AudioSource (Spatial Blend=0, Mute=off).
/// </summary>
[RequireComponent(typeof(AudioSource))]
public class SimulationAudio : MonoBehaviour
{
    [Header("Carrier Frequency Mapping (Hz)")]
    public float carrierMinHz = 220f;       // intensity=0 时音调
    public float carrierMaxHz = 660f;       // intensity=1 时音调

    [Header("Volume")]
    [Range(0f, 1f)] public float baseVolume = 0.3f;
    [Range(0f, 1f)] public float noiseBelowThreshold = 0.05f;

    [Header("Shot Sound Effects")]
    [Tooltip("Success fanfare duration (s)")]
    public float fanfareDuration = 0.6f;
    [Tooltip("Failure descending-tone duration (s)")]
    public float failTonePauseDuration = 0.3f;

    [Header("Debug")]
    public bool showCurrentToneHz = true;
    public float currentToneHz = 220f;

    // --- 合成器内部状态 (audio thread 读写) ---
    private double phase;                   // 载波相位
    private double sampleRateD;
    private float targetIntensity = 0f;     // 主线程写, 音频线程读
    private float thresholdRef = 0.65f;     // 同上
    private bool audioEnabled = true;       // 模态开关

    // 击发 envelope: 0 表示无击发, >0 表示剩余时间
    private float fireEnvelopeRemaining = 0f;
    private float fireEnvelopeTotal = 0f;
    private bool fireIsHit = false;

    // 失败音: 单独保存起始频率
    private double failPhase = 0;

    private System.Random rng = new System.Random();

    // 主线程引用
    private SimulationGameManager.TrialState lastObservedState = SimulationGameManager.TrialState.Idle;

    void Awake()
    {
        sampleRateD = AudioSettings.outputSampleRate;
        var src = GetComponent<AudioSource>();
        src.playOnAwake = true;
        src.loop = true;
        src.spatialBlend = 0f;
        src.volume = 1f;
        // 没有 clip 也能产生 OnAudioFilterRead 数据? 在某些 Unity 版本里需要一个 dummy clip.
        // 实测: 只要 AudioSource.Play() 被调用且组件 enabled, 即使无 clip 也会进入 OnAudioFilterRead.
        if (src.clip == null)
        {
            // 创建一个 1 秒静音 clip 当占位, 保证 Play 链路通
            var clip = AudioClip.Create("SimAudioDummy", (int)sampleRateD, 1, AudioSettings.outputSampleRate, false);
            src.clip = clip;
        }
        src.Play();
    }

    void Update()
    {
        var sm = SimulationGameManager.Instance;
        if (sm == null) { audioEnabled = false; return; }

        // 模态过滤: DEV_PLAN 三 — 通道由 MATLAB 运行时下发, 读 BCIDataHub
        var hub = BCIDataHub.Instance;
        Modality m = (hub != null) ? hub.currentModality : Modality.Both;
        audioEnabled = (m == Modality.Auditory || m == Modality.Both);

        targetIntensity = Mathf.Clamp01(sm.currentIntensity);
        thresholdRef = sm.threshold;
        currentToneHz = Mathf.Lerp(carrierMinHz, carrierMaxHz, targetIntensity);

        // 状态切换 → 触发击发音
        if (sm.state != lastObservedState)
        {
            if (sm.state == SimulationGameManager.TrialState.Fired)
            {
                fireIsHit = sm.lastWasHit;
                fireEnvelopeTotal = fireIsHit ? fanfareDuration : failTonePauseDuration;
                fireEnvelopeRemaining = fireEnvelopeTotal;
                failPhase = 0;
            }
            lastObservedState = sm.state;
        }
    }

    void OnAudioFilterRead(float[] data, int channels)
    {
        if (!audioEnabled)
        {
            // 模态不启用 → 写零
            for (int i = 0; i < data.Length; i++) data[i] = 0f;
            return;
        }

        float freq = Mathf.Lerp(carrierMinHz, carrierMaxHz, targetIntensity);
        double phaseInc = 2.0 * System.Math.PI * freq / sampleRateD;
        bool belowThr = targetIntensity < thresholdRef;
        float dt = 1f / (float)sampleRateD;

        for (int i = 0; i < data.Length; i += channels)
        {
            phase += phaseInc;
            if (phase > 2.0 * System.Math.PI) phase -= 2.0 * System.Math.PI;

            // ---- 基础载波 ----
            float sample = (float)System.Math.Sin(phase) * baseVolume;

            // ---- 噪声 (低于阈值时) ----
            if (belowThr)
            {
                float noise = (float)(rng.NextDouble() * 2.0 - 1.0) * noiseBelowThreshold;
                sample += noise;
            }

            // ---- 击发音 envelope ----
            if (fireEnvelopeRemaining > 0f)
            {
                float env = fireEnvelopeRemaining / fireEnvelopeTotal;   // 1 → 0
                if (fireIsHit)
                {
                    // 大三和弦 C5(523) E5(659) G5(784) + C6(1046)
                    double t = phase / phaseInc / sampleRateD;            // 大致的全局时间, 仅作相位偏移
                    sample += env * 0.25f * Mathf.Sin((float)(2 * System.Math.PI * 523.25 * t));
                    sample += env * 0.20f * Mathf.Sin((float)(2 * System.Math.PI * 659.25 * t));
                    sample += env * 0.20f * Mathf.Sin((float)(2 * System.Math.PI * 783.99 * t));
                    sample += env * 0.15f * Mathf.Sin((float)(2 * System.Math.PI * 1046.5 * t));
                }
                else
                {
                    // 失败: 220 → 110 Hz 下降扫频
                    float failFreq = Mathf.Lerp(110f, 220f, env);
                    failPhase += 2.0 * System.Math.PI * failFreq / sampleRateD;
                    if (failPhase > 2.0 * System.Math.PI) failPhase -= 2.0 * System.Math.PI;
                    sample += env * 0.35f * (float)System.Math.Sin(failPhase);
                }
                fireEnvelopeRemaining -= dt;
                if (fireEnvelopeRemaining < 0f) fireEnvelopeRemaining = 0f;
            }

            // ---- 输出到所有通道 ----
            for (int c = 0; c < channels; c++)
            {
                data[i + c] = sample;
            }
        }
    }
}
