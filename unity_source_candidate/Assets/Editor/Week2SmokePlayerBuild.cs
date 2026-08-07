#if UNITY_EDITOR
using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEngine;

public static class Week2SmokePlayerBuild
{
    public static void BuildWindowsSmokePlayer()
    {
        string root = "Builds/Smoke";
        Directory.CreateDirectory(root);
        string[] scenes = {
            "Assets/Scenes/_Bootstrap.unity",
            "Assets/Scenes/MainMenu.unity",
            "Assets/Scenes/Game_Simulation3D.unity"
        };
        var options = new BuildPlayerOptions {
            scenes = scenes,
            locationPathName = root + "/SPNFT_Smoke.exe",
            target = BuildTarget.StandaloneWindows64,
            options = BuildOptions.Development
        };
        var report = BuildPipeline.BuildPlayer(options);
        if (report.summary.result != UnityEditor.Build.Reporting.BuildResult.Succeeded)
        {
            throw new BuildFailedException("Week 2 smoke player build failed: " + report.summary.result);
        }
        Debug.Log("[Week2Build] Built " + options.locationPathName);
    }
}
#endif
