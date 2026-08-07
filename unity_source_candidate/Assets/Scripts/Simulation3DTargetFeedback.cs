using UnityEngine;

public class Simulation3DTargetFeedback : MonoBehaviour
{
    public Renderer paperRenderer;
    public Transform impactRoot;
    public Color idleColor = new Color(0.92f, 0.9f, 0.84f, 1f);
    public Color hitColor = new Color(1f, 0.86f, 0.42f, 1f);
    public Color missColor = new Color(0.72f, 0.34f, 0.34f, 1f);
    public float flashDuration = 0.55f;
    public float impactMarkerScale = 0.06f;
    public int maxImpactMarkers = 24;

    private Color currentBaseColor;
    private float flashTimer;
    private int shotIndex;

    void Awake()
    {
        if (paperRenderer == null) paperRenderer = GetComponentInChildren<Renderer>();
        if (impactRoot == null)
        {
            var root = new GameObject("ImpactMarkers");
            root.transform.SetParent(transform, false);
            impactRoot = root.transform;
        }
        currentBaseColor = idleColor;
        ApplyColor(idleColor);
    }

    void Update()
    {
        if (flashTimer <= 0f) return;

        flashTimer -= Time.deltaTime;
        float t = Mathf.Clamp01(flashTimer / flashDuration);
        ApplyColor(Color.Lerp(currentBaseColor, idleColor, 1f - t));
        if (flashTimer <= 0f)
        {
            currentBaseColor = idleColor;
            ApplyColor(idleColor);
        }
    }

    public void PlayShot(int rings, bool isHit)
    {
        currentBaseColor = isHit ? hitColor : missColor;
        flashTimer = flashDuration;
        ApplyColor(currentBaseColor);
        CreateImpactMarker(rings, isHit);
    }

    void ApplyColor(Color color)
    {
        if (paperRenderer == null) return;
        paperRenderer.material.color = color;
    }

    void CreateImpactMarker(int rings, bool isHit)
    {
        if (impactRoot == null) return;

        while (impactRoot.childCount >= maxImpactMarkers)
        {
            Destroy(impactRoot.GetChild(0).gameObject);
        }

        var marker = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        marker.name = isHit ? $"Hit_{shotIndex}" : $"Miss_{shotIndex}";
        shotIndex++;
        marker.transform.SetParent(impactRoot, false);
        marker.transform.localPosition = ComputeImpactLocalPosition(rings, isHit);
        marker.transform.localScale = Vector3.one * impactMarkerScale;
        var collider = marker.GetComponent<Collider>();
        if (collider != null) Destroy(collider);

        var renderer = marker.GetComponent<Renderer>();
        if (renderer != null)
        {
            renderer.material.color = isHit
                ? new Color(0.12f, 0.12f, 0.12f, 1f)
                : new Color(0.6f, 0.16f, 0.16f, 1f);
        }
    }

    Vector3 ComputeImpactLocalPosition(int rings, bool isHit)
    {
        float angle = shotIndex * 137.5f * Mathf.Deg2Rad;
        if (!isHit)
        {
            float missRadius = 0.62f;
            return new Vector3(Mathf.Cos(angle) * missRadius, Mathf.Sin(angle) * missRadius, -0.04f);
        }

        float normalized = Mathf.InverseLerp(10f, 5f, Mathf.Clamp(rings, 5, 10));
        float radius = Mathf.Lerp(0.03f, 0.38f, normalized);
        return new Vector3(Mathf.Cos(angle) * radius, Mathf.Sin(angle) * radius, -0.04f);
    }
}
