using UnityEngine;
using UnityEngine.SceneManagement;

public class BootstrapLoader : MonoBehaviour
{
    public string firstSceneToLoad = "MainMenu";

    void Start()
    {
        // 把主菜单场景加载到 Bootstrap 之上（Additive 让 BCISystem 不被销毁）
        SceneManager.LoadScene(firstSceneToLoad, LoadSceneMode.Additive);
    }
}