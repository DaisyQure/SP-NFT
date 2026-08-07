using UnityEngine;
using UnityEngine.UI;

/// <summary>
/// 圆环靶高亮控制器。挂在 Target 物体上。
/// 命中时根据环数让对应圈短暂高亮 (变亮 + 轻微缩放), 其他圈保持暗色。
/// 5 环也命中, 但视觉上只让 Ring6 (即外圈本体, 即挂这个脚本的 Image) 轻闪。
/// </summary>
public class TargetRings : MonoBehaviour
{
    [Tooltip("Ring 7 (blue)")] public Image ring7;
    [Tooltip("Ring 8 (red)")] public Image ring8;
    [Tooltip("Ring 9 (yellow)")] public Image ring9;
    [Tooltip("Ring 10 (white bullseye)")] public Image ring10;

    [Tooltip("Highlight duration")] public float highlightDuration = 0.8f;
    [Tooltip("Grayscale target color after a miss")] public Color missTint = new Color(0.55f, 0.55f, 0.55f, 1f);

    private Color[] baseColors;
    private Image[] rings;
    private int highlightedIndex = -1;
    private float timer = 0f;
    private bool initialized;

    void Awake()
    {
        EnsureInitialized();
    }

    /// <summary>由 SimulationUI 在 Fired 状态调用</summary>
    public void Highlight(int rings_, bool isHit)
    {
        EnsureInitialized();
        ResetColors();
        timer = highlightDuration;

        if (!isHit)
        {
            // 失败: 整体变灰
            for (int i = 0; i < rings.Length; i++)
                if (rings[i] != null) rings[i].color = missTint;
            highlightedIndex = -1;
            return;
        }

        // 命中: 环数 5/6 → index 0; 7→1; 8→2; 9→3; 10→4
        int idx = Mathf.Clamp(rings_ - 6, 0, 4);
        highlightedIndex = idx;
        if (rings[idx] != null)
        {
            // 命中圈轻微缩放 + 颜色提亮
            rings[idx].color = Color.Lerp(baseColors[idx], Color.white, 0.5f);
            rings[idx].rectTransform.localScale = Vector3.one * 1.15f;
        }
    }

    void Update()
    {
        if (timer > 0f)
        {
            timer -= Time.deltaTime;
            if (timer <= 0f)
            {
                ResetColors();
            }
            else if (highlightedIndex >= 0 && rings[highlightedIndex] != null)
            {
                // 缩放回弹
                float t = 1f - Mathf.Clamp01(timer / highlightDuration);
                float scale = Mathf.Lerp(1.15f, 1f, t);
                rings[highlightedIndex].rectTransform.localScale = Vector3.one * scale;
            }
        }
    }

    void ResetColors()
    {
        EnsureInitialized();
        for (int i = 0; i < rings.Length; i++)
        {
            if (rings[i] != null)
            {
                rings[i].color = baseColors[i];
                rings[i].rectTransform.localScale = Vector3.one;
            }
        }
        highlightedIndex = -1;
    }

    void EnsureInitialized()
    {
        if (initialized) return;

        var selfImg = GetComponent<Image>();
        rings = new Image[] { selfImg, ring7, ring8, ring9, ring10 };
        baseColors = new Color[rings.Length];
        for (int i = 0; i < rings.Length; i++)
        {
            if (rings[i] != null) baseColors[i] = rings[i].color;
        }

        initialized = true;
    }
}
