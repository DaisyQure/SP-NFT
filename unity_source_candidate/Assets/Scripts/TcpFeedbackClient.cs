using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using UnityEngine;
using UnityEngine.SceneManagement;

public class TcpFeedbackClient : MonoBehaviour
{
    public static TcpFeedbackClient Instance { get; private set; }

    [Header("Server")]
    public string serverIp = "127.0.0.1";
    public int serverPort = 5555;
    public bool connectOnStart = true;

    [Header("Automatic Reconnection")]
    public bool autoReconnect = true;
    public float reconnectInterval = 2f;

    [Header("Dependencies (leave empty for automatic lookup)")]
    public AttentionLogger logger;

    [Header("State (Runtime Read-only)")]
    public bool isConnected = false;
    public string lastError = "";
    public int appliedCount = 0;
    public int queuePeak = 0;
    public int sentMarkerCount = 0;
    public int reconnectAttempts = 0;

    private TcpClient client;
    private NetworkStream stream;
    private Thread receiveThread;
    private volatile bool shouldStop = false;
    private bool sceneEventsRegistered = false;
    private float nextReconnectTime = 0f;

    private readonly ConcurrentQueue<FeedbackMsg> incomingQueue = new ConcurrentQueue<FeedbackMsg>();
    private int markerSeq = 0;

    void Awake()
    {
        Instance = this;
    }

    void Start()
    {
        if (BCIDataHub.Instance == null)
        {
            Debug.LogError("[TCP] BCIDataHub was not found.");
            return;
        }

        if (logger == null) logger = GetComponent<AttentionLogger>();
        if (logger == null) logger = FindObjectOfType<AttentionLogger>();
        if (logger == null)
            Debug.LogWarning("[TCP] AttentionLogger was not found; latency will not be recorded in this run.");

        RegisterSceneEvents();

        if (connectOnStart) TryConnect();
    }

    void Update()
    {
        // Automatic Reconnection
        if (autoReconnect && !isConnected && Time.realtimeSinceStartup >= nextReconnectTime)
        {
            nextReconnectTime = Time.realtimeSinceStartup + reconnectInterval;
            TryConnect();
        }

        int drained = 0;
        while (incomingQueue.TryDequeue(out FeedbackMsg msg))
        {
            double tsUnityApply = AttentionLogger.NowPosix();
            BCIDataHub.Instance.UpdateFromMessage(msg);
            if (logger != null) logger.LogSample(msg, tsUnityApply);
            appliedCount++;
            drained++;
        }
        if (drained > queuePeak) queuePeak = drained;
    }

    void TryConnect()
    {
        if (isConnected) return;
        try
        {
            client = new TcpClient();
            client.Connect(serverIp, serverPort);
            stream = client.GetStream();
            isConnected = true;
            shouldStop = false;
            receiveThread = new Thread(ReceiveLoop) { IsBackground = true };
            receiveThread.Start();
            reconnectAttempts = 0;
            Debug.Log($"[TCP] Connected to {serverIp}:{serverPort}");
            SendMarker("tcp_connected", 0f, $"{serverIp}:{serverPort}");
        }
        catch (Exception e)
        {
            isConnected = false;
            lastError = e.Message;
            reconnectAttempts++;
            if (reconnectAttempts == 1 || reconnectAttempts % 10 == 0)
            {
                Debug.LogWarning($"[TCP] Connection failed (attempt #{reconnectAttempts}): {e.Message}");
            }
        }
    }

    public void Connect()
    {
        TryConnect();
    }

    public void SendMarker(string evt, float value = 0f, string info = "")
    {
        if (!isConnected || stream == null) return;
        try
        {
            var m = new MarkerMsg
            {
                seq = markerSeq++,
                ts = AttentionLogger.NowPosix(),
                evt = evt,
                scene = SceneManager.GetActiveScene().name,
                value = value,
                info = info
            };
            string json = JsonUtility.ToJson(m) + "\n";
            byte[] bytes = Encoding.UTF8.GetBytes(json);
            stream.Write(bytes, 0, bytes.Length);
            sentMarkerCount++;
        }
        catch (Exception e)
        {
            Debug.LogWarning($"[Marker] Send failed: {e.Message}");
            isConnected = false;
        }
    }

    void ReceiveLoop()
    {
        byte[] buffer = new byte[8192];
        var lineBytes = new List<byte>(8192);
        try
        {
            while (!shouldStop && client != null && client.Connected)
            {
                if (stream.DataAvailable)
                {
                    int n = stream.Read(buffer, 0, buffer.Length);
                    if (n <= 0) break;

                    for (int i = 0; i < n; i++)
                    {
                        byte b = buffer[i];
                        if (b == (byte)'\n')
                        {
                            string line = Encoding.UTF8.GetString(lineBytes.ToArray()).Trim();
                            lineBytes.Clear();
                            if (line.Length > 0) ProcessLine(line);
                        }
                        else if (b != (byte)'\r')
                        {
                            lineBytes.Add(b);
                        }
                    }
                }
                else Thread.Sleep(1);
            }

            if (lineBytes.Count > 0)
            {
                string tail = Encoding.UTF8.GetString(lineBytes.ToArray()).Trim();
                if (tail.Length > 0) ProcessLine(tail);
            }
        }
        catch (Exception e)
        {
            lastError = e.Message;
            Debug.LogWarning($"[TCP] Receive thread stopped: {e.Message}");
        }
        finally
        {
            isConnected = false;
            try { stream?.Close(); } catch { }
            try { client?.Close(); } catch { }
            stream = null;
            client = null;
        }
    }

    void ProcessLine(string json)
    {
        try
        {
            var msg = JsonUtility.FromJson<FeedbackMsg>(json);
            if (msg == null) return;
            msg.tsUnityRecv = AttentionLogger.NowPosix();
            incomingQueue.Enqueue(msg);
        }
        catch (Exception e)
        {
            Debug.LogWarning($"[TCP] Parse failed: {json} | {e.Message}");
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
        SendMarker("scene_loaded", 0f, scene.name);
    }

    void OnSceneUnloaded(Scene scene)
    {
        SendMarker("scene_unloaded", 0f, scene.name);
    }

    public void Disconnect()
    {
        autoReconnect = false;
        if (isConnected)
            SendMarker("tcp_disconnected", 0f, lastError);

        shouldStop = true;
        try { stream?.Close(); } catch { }
        try { client?.Close(); } catch { }
        isConnected = false;
    }

    void OnApplicationQuit()
    {
        Disconnect();
        UnregisterSceneEvents();
    }

    void OnDestroy()
    {
        Disconnect();
        UnregisterSceneEvents();
    }
}

[System.Serializable]
public class MarkerMsg
{
    public int seq;
    public double ts;
    public string evt;
    public string scene;
    public float value;
    public string info;
}
