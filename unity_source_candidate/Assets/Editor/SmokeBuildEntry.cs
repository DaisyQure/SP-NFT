#if UNITY_EDITOR
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class SmokeBuildEntry
{
    public static void OpenBootstrapSceneForSmoke()
    {
        string scenePath = "Assets/Scenes/_Bootstrap.unity";
        if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo())
        {
            Debug.LogWarning("[SmokeBuildEntry] Scene switch cancelled by user.");
            return;
        }

        var scene = EditorSceneManager.OpenScene(scenePath, OpenSceneMode.Single);
        Debug.Log($"[SmokeBuildEntry] Opened scene: {scene.path}");

        EditorApplication.delayCall += EnterPlayModeOnce;
    }

    static void EnterPlayModeOnce()
    {
        EditorApplication.delayCall -= EnterPlayModeOnce;
        if (EditorApplication.isPlayingOrWillChangePlaymode)
        {
            return;
        }

        Debug.Log("[SmokeBuildEntry] Entering Play Mode for smoke run.");
        EditorApplication.isPlaying = true;
    }
}
#endif
