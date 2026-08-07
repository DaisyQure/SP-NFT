using UnityEngine;

/// <summary>
/// Adaptive Progression阈值适配器 (Step S4)
/// 每 N 试次评估命中率, 自动抬/降阈值。
/// 命中率 ≥ raiseHitRate → 抬阈值
/// 命中率 ≤ lowerHitRate → 降阈值
/// 区间内 → 保持
///
/// 通过 marker 通道把调整事件回报 MATLAB 端供监控/可视化。
/// </summary>
public class ThresholdAdapter : MonoBehaviour
{
    [Header("Adaptive Progression")]
    [Tooltip("Evaluate every N trials")]
    public int evaluateEveryNTrials = 5;
    [Tooltip("Raise the threshold when hit rate is at or above this value")]
    [Range(0f, 1f)] public float raiseHitRate = 0.7f;
    [Tooltip("Lower the threshold when hit rate is at or below this value")]
    [Range(0f, 1f)] public float lowerHitRate = 0.5f;
    [Tooltip("Adjustment step")]
    public float thresholdStep = 0.05f;
    [Tooltip("Threshold limits")]
    public float thresholdMin = 0.4f;
    public float thresholdMax = 0.9f;

    [Header("Debug (Read-only)")]
    public float lastWindowHitRate = 0f;
    public string lastDirection = "-";   // "raise" / "lower" / "hold"
    public int evaluationCount = 0;

    private int lastEvalTrial = 0;
    private int hitsAtLastEval = 0;

    public void OnTrialFinished(int currentTrial, int hitsCount)
    {
        if (currentTrial - lastEvalTrial < evaluateEveryNTrials) return;

        int windowHits = hitsCount - hitsAtLastEval;
        int windowTrials = currentTrial - lastEvalTrial;
        float hitRate = (float)windowHits / windowTrials;
        lastWindowHitRate = hitRate;
        evaluationCount++;

        var sm = SimulationGameManager.Instance;
        if (sm == null) return;
        float old = sm.threshold;
        float newThreshold = old;
        string direction = "hold";

        if (hitRate >= raiseHitRate)
        {
            newThreshold = Mathf.Min(thresholdMax, old + thresholdStep);
            direction = "raise";
        }
        else if (hitRate <= lowerHitRate)
        {
            newThreshold = Mathf.Max(thresholdMin, old - thresholdStep);
            direction = "lower";
        }
        lastDirection = direction;

        // marker payload 编码: 整数部分 = 方向 (1=raise, 2=lower, 0=hold)
        // 小数部分 = 新阈值;  例: 1.70 = raise to 0.70, 2.60 = lower to 0.60, 0.65 = hold@0.65
        float payload;
        switch (direction)
        {
            case "raise": payload = 1f + newThreshold; break;
            case "lower": payload = 2f + newThreshold; break;
            default:      payload = newThreshold;      break;
        }

        if (!Mathf.Approximately(newThreshold, old))
        {
            sm.threshold = newThreshold;
            Debug.Log($"[ThresholdAdapter] eval#{evaluationCount} trial={currentTrial} hits={windowHits}/{windowTrials} ({hitRate:P0}) → {direction} {old:F2}→{newThreshold:F2}");
            TcpFeedbackClient.Instance?.SendMarker("threshold_adjusted", payload, "simulation");
        }
        else
        {
            Debug.Log($"[ThresholdAdapter] eval#{evaluationCount} trial={currentTrial} hits={windowHits}/{windowTrials} ({hitRate:P0}) → hold @{old:F2}");
            TcpFeedbackClient.Instance?.SendMarker("threshold_hold", hitRate, "simulation");
        }

        lastEvalTrial = currentTrial;
        hitsAtLastEval = hitsCount;
    }
}
