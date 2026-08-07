using UnityEngine;
using UnityEngine.SceneManagement;

public class SchemeSceneRouter : MonoBehaviour
{
    private static SchemeSceneRouter instance;
    private bool routed;

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    private static void AutoBootstrap()
    {
        if (instance != null) return;
        var go = new GameObject("SchemeSceneRouter");
        instance = go.AddComponent<SchemeSceneRouter>();
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
    }

    void Update()
    {
        if (routed) return;
        var hub = BCIDataHub.Instance;
        if (hub == null) return;
        if (string.IsNullOrEmpty(hub.currentScheme)) return;

        string target = ResolveTargetScene(hub.currentScheme);
        if (string.IsNullOrEmpty(target)) return;

        var targetScene = SceneManager.GetSceneByName(target);
        if (targetScene.IsValid() && targetScene.isLoaded)
        {
            if (SceneManager.GetActiveScene().name != target)
            {
                SceneManager.SetActiveScene(targetScene);
            }
            return;
        }

        routed = true;
        StartCoroutine(RouteToScene(target));
    }

    System.Collections.IEnumerator RouteToScene(string targetScene)
    {
        var hub = BCIDataHub.Instance;
        if (hub != null && hub.armedSceneName != targetScene)
        {
            hub.ArmForScene(targetScene);
        }

        TcpFeedbackClient.Instance?.SendMarker("scheme_scene_route", 0f, targetScene);

        var current = SceneManager.GetActiveScene();
        if (current.IsValid() && current.name != "_Bootstrap" && current.name != targetScene)
        {
            var unload = SceneManager.UnloadSceneAsync(current.name);
            while (unload != null && !unload.isDone)
                yield return null;
        }

        var existing = SceneManager.GetSceneByName(targetScene);
        if (!existing.isLoaded)
        {
            var load = SceneManager.LoadSceneAsync(targetScene, LoadSceneMode.Additive);
            while (load != null && !load.isDone)
                yield return null;
        }

        existing = SceneManager.GetSceneByName(targetScene);
        if (existing.IsValid() && existing.isLoaded)
        {
            SceneManager.SetActiveScene(existing);
        }

        routed = false;
    }

    static string ResolveTargetScene(string scheme)
    {
        switch (scheme)
        {
            case "simulation":
                return MainMenuController.SimulationSceneName;
            case "relax":
                return "Game_Relax";
            case "monitor":
                return "Game_Monitor";
            case "attention":
            default:
                return "Game_Attention";
        }
    }
}
