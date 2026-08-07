using System;
using System.Collections.Concurrent;
using System.Globalization;
using System.IO;
using UnityEngine;

public class AttentionLogger : MonoBehaviour
{
    [Header("Logging")]
    public bool enableLogging = true;

    [Header("File Settings")]
    [Tooltip("Leave empty to use the default directory, or enter an absolute path. See GetDefaultOutputDir().")]
    public string outputDir = "";
    [Tooltip("Filename prefix; a timestamp is appended automatically")]
    public string filePrefix = "bci_log";

    [Header("Write Strategy")]
    [Tooltip("Flush after this many rows to reduce data loss after a crash")]
    public int flushEvery = 50;

    [Header("State (Runtime Read-only)")]
    public string currentFilePath = "";
    public int writtenCount = 0;
    public float lastLatencyMs = 0f;
    public float avgLatencyMs = 0f;
    public float minLatencyMs = 0f;
    public float maxLatencyMs = 0f;

    private StreamWriter writer;
    private readonly ConcurrentQueue<LogRow> queue = new ConcurrentQueue<LogRow>();
    private int sinceFlush = 0;
    private double latencySum = 0;

    public struct LogRow
    {
        public int seq;
        public string type;
        public double tsMatlab;
        public double tsUnityRecv;
        public double tsUnityApply;
        public float value;
    }

    void Start()
    {
        if (!enableLogging) return;
        OpenFile();
    }

    void OpenFile()
    {
        try
        {
            string dir = string.IsNullOrEmpty(outputDir)
                ? GetDefaultOutputDir()
                : outputDir;
            Directory.CreateDirectory(dir);

            string stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            currentFilePath = Path.Combine(dir, $"{filePrefix}_{stamp}.csv");

            writer = new StreamWriter(currentFilePath, false, System.Text.Encoding.UTF8);
            writer.WriteLine("seq,type,ts_matlab,ts_unity_recv,ts_unity_apply,value,transport_ms,queue_ms,latency_ms");
            writer.Flush();

            Debug.Log($"[Logger] Writing to: {currentFilePath}");
        }
        catch (Exception e)
        {
            Debug.LogError($"[Logger] Failed to open file: {e.Message}");
            enableLogging = false;
        }
    }

    static string GetDefaultOutputDir()
    {
        string configured = Environment.GetEnvironmentVariable("SPNFT_LOG_ROOT");
        if (!string.IsNullOrWhiteSpace(configured))
            return Path.Combine(configured, "BCILog");
        return Path.Combine(Application.persistentDataPath, "BCILog");
    }

    /// <summary>
    /// 由 TcpFeedbackClient 在主线程应用消息时调用。
    /// 所有字段此刻都已确定,这里只入队,写盘交给 Update —— 不在调用方做 IO。
    /// </summary>
    public void LogSample(FeedbackMsg msg, double tsUnityApply)
    {
        if (!enableLogging) return;
        queue.Enqueue(new LogRow
        {
            seq = msg.seq,
            type = msg.type,
            tsMatlab = msg.ts,
            tsUnityRecv = msg.tsUnityRecv,
            tsUnityApply = tsUnityApply,
            value = msg.value
        });
    }

    void Update()
    {
        if (!enableLogging || writer == null) return;

        while (queue.TryDequeue(out LogRow row))
        {
            // 三段延迟拆分
            double transport = (row.tsUnityRecv - row.tsMatlab) * 1000.0; // MATLAB发出→Unity收到
            double queueMs = (row.tsUnityApply - row.tsUnityRecv) * 1000.0;  // 收到→主线程应用
            double latency = (row.tsUnityApply - row.tsMatlab) * 1000.0;  // 端到端总延迟

            writer.WriteLine(string.Format(CultureInfo.InvariantCulture,
                "{0},{1},{2:F6},{3:F6},{4:F6},{5:F4},{6:F3},{7:F3},{8:F3}",
                row.seq, row.type, row.tsMatlab, row.tsUnityRecv, row.tsUnityApply,
                row.value, transport, queueMs, latency));

            writtenCount++;
            sinceFlush++;
            latencySum += latency;
            lastLatencyMs = (float)latency;
            avgLatencyMs = (float)(latencySum / writtenCount);
            if (writtenCount == 1 || latency < minLatencyMs) minLatencyMs = (float)latency;
            if (latency > maxLatencyMs) maxLatencyMs = (float)latency;

            if (sinceFlush >= flushEvery)
            {
                writer.Flush();
                sinceFlush = 0;
            }
        }
    }

    public static double NowPosix()
    {
        return (DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc))
            .TotalSeconds;
    }

    void OnApplicationQuit() { Close(); }
    void OnDestroy() { Close(); }

    void Close()
    {
        if (writer != null)
        {
            try { writer.Flush(); writer.Close(); } catch { }
            writer = null;
            Debug.Log($"[Logger] Closed after writing {writtenCount} rows: {currentFilePath}");
        }
    }
}
