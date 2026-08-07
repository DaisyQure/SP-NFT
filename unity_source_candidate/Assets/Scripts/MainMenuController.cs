using UnityEngine;
using UnityEngine.SceneManagement;

public class MainMenuController : MonoBehaviour
{
    public const string SimulationSceneName = "Game_Simulation3D";

    public void LoadShooter()
    {
        LoadGame(SimulationSceneName, "menu_select_simulation");
    }

    public void LoadAttention()
    {
        LoadGame("Game_Attention", "menu_select_attention");
    }

    public void LoadRelax()
    {
        LoadGame("Game_Relax", "menu_select_relax");
    }

    public void LoadMonitor()
    {
        LoadGame("Game_Monitor", "menu_select_monitor");
    }

    void LoadGame(string sceneName, string menuEvent)
    {
        BCIDataHub.Instance?.ArmForScene(sceneName);
        TcpFeedbackClient.Instance?.SendMarker(menuEvent, 0f, sceneName);
        SceneManager.UnloadSceneAsync("MainMenu");
        SceneManager.LoadScene(sceneName, LoadSceneMode.Additive);
    }
}
