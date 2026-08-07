using TMPro;
using UnityEngine;
using UnityEngine.UI;

public class SimulationUI : MonoBehaviour
{
    [Header("HUD")]
    public TextMeshProUGUI trialText;
    public TextMeshProUGUI thresholdText;
    public TextMeshProUGUI hitsText;
    public TextMeshProUGUI stateText;
    public TextMeshProUGUI scoreText;
    public TextMeshProUGUI intensityText;
    public TextMeshProUGUI lastShotText;

    [Header("Intensity Bar")]
    public Image intensityBarFill;
    public RectTransform thresholdLine;
    public RectTransform intensityBarBackground;

    [Header("Virtual Arm")]
    public RectTransform virtualArm;
    public float armDownY = -300f;
    public float armAimY = -50f;

    [Header("Target")]
    public Image target;
    public TargetRings targetRings;
    public Color targetIdleColor = new Color(1f, 1f, 1f, 1f);
    public Color targetHitColor = new Color(1f, 0.85f, 0.2f, 1f);
    public Color targetMissColor = new Color(0.6f, 0.6f, 0.6f, 0.6f);
    public float targetFlashDuration = 0.5f;

    [Header("Fire FX")]
    public Image screenFlash;
    public TextMeshProUGUI ringsPopup;
    public float fireFlashDuration = 0.25f;
    public float ringsPopupDuration = 1.2f;
    public Color ringsGoldColor = new Color(1f, 0.85f, 0.2f, 1f);
    public Color ringsSilverColor = new Color(0.85f, 0.85f, 0.9f, 1f);
    public Color ringsBronzeColor = new Color(0.85f, 0.55f, 0.3f, 1f);
    public Color ringsMissColor = new Color(0.6f, 0.6f, 0.6f, 1f);

    [Header("Colors")]
    public Color stateAimingColor = new Color(0.8f, 0.9f, 1f, 1f);
    public Color stateReadyColor = new Color(0.2f, 0.85f, 0.3f, 1f);
    public Color stateFiredColor = new Color(1f, 0.75f, 0.2f, 1f);
    public Color stateFailColor = new Color(0.9f, 0.3f, 0.3f, 1f);

    [Header("3D Upgrade")]
    public bool hideLegacy2DVisuals = false;
    public bool autoCreateDebugHudIfMissing = false;

    private float targetFlashTimer;
    private float flashTimer;
    private float ringsPopupTimer;
    private SimulationGameManager.TrialState lastObservedState = SimulationGameManager.TrialState.Idle;
    private Modality lastModality = Modality.Both;
    private bool modalityInitialized;
    private bool lastHideLegacy2DVisuals;
    private bool hasShotResult;


    void Start()
    {
        EnsureDebugHud();
    }

    void Update()
    {
        EnsureDebugHud();

        var sm = SimulationGameManager.Instance;
        if (sm == null) return;

        var hub = BCIDataHub.Instance;
        Modality curModality = (hub != null) ? hub.currentModality : Modality.Both;
        if (!modalityInitialized || curModality != lastModality || hideLegacy2DVisuals != lastHideLegacy2DVisuals)
        {
            ApplyModalityVisibility(curModality);
            lastModality = curModality;
            lastHideLegacy2DVisuals = hideLegacy2DVisuals;
            modalityInitialized = true;
        }

        if (sm.state != lastObservedState)
        {
            OnStateChanged(lastObservedState, sm.state);
            lastObservedState = sm.state;
        }

        if (trialText != null)
            trialText.text = $"Trial: {sm.currentTrial}/{sm.trialCount}";
        if (thresholdText != null)
            thresholdText.text = $"Threshold: {sm.threshold:F2}";
        if (hitsText != null)
            hitsText.text = $"Hits: {sm.hitsCount}/{Mathf.Max(sm.currentTrial - (sm.state == SimulationGameManager.TrialState.Aiming ? 1 : 0), 0)}";
        if (scoreText != null)
            scoreText.text = $"Score: {sm.totalScore}";
        if (intensityText != null)
            intensityText.text = $"Intensity: {sm.currentIntensity:F2}";
        if (lastShotText != null)
        {
            if (!hasShotResult) lastShotText.text = "Last Shot: --";
            else if (sm.lastWasHit) lastShotText.text = $"Last Shot: {sm.lastRings} rings";
            else lastShotText.text = "Last Shot: MISS";
        }

        if (stateText != null)
        {
            switch (sm.state)
            {
                case SimulationGameManager.TrialState.Aiming:
                    if (sm.aboveThresholdDuration > 0f)
                    {
                        stateText.text = $"State: HOLD {sm.aboveThresholdDuration:F1}s / {sm.holdTimeSec:F1}s";
                        stateText.color = stateReadyColor;
                    }
                    else
                    {
                        stateText.text = "State: AIMING";
                        stateText.color = stateAimingColor;
                    }
                    break;
                case SimulationGameManager.TrialState.ReadyToFire:
                    stateText.text = "State: FIRING!";
                    stateText.color = stateReadyColor;
                    break;
                case SimulationGameManager.TrialState.Fired:
                    stateText.text = "State: TRIAL DONE";
                    stateText.color = stateFiredColor;
                    break;
                case SimulationGameManager.TrialState.Reset:
                    stateText.text = "State: RESET";
                    stateText.color = stateAimingColor;
                    break;
                case SimulationGameManager.TrialState.Idle:
                    stateText.text = sm.sessionFinished ? "State: SESSION COMPLETE" : "State: READY";
                    stateText.color = stateAimingColor;
                    break;
            }
        }

        if (intensityBarFill != null)
        {
            intensityBarFill.fillAmount = Mathf.Clamp01(sm.currentIntensity);
            if (sm.currentIntensity >= sm.threshold)
                intensityBarFill.color = new Color(0.2f, 0.85f, 0.3f, 1f);
            else if (sm.currentIntensity >= sm.threshold * 0.7f)
                intensityBarFill.color = new Color(0.95f, 0.75f, 0.2f, 1f);
            else
                intensityBarFill.color = new Color(0.4f, 0.7f, 1f, 1f);
        }

        if (thresholdLine != null && intensityBarBackground != null)
        {
            float barHeight = intensityBarBackground.rect.height;
            float lineY = (sm.threshold - 0.5f) * barHeight;
            Vector2 pos = thresholdLine.anchoredPosition;
            pos.y = lineY;
            thresholdLine.anchoredPosition = pos;
        }

        if (!hideLegacy2DVisuals && virtualArm != null)
        {
            float y = Mathf.Lerp(armDownY, armAimY, Mathf.Clamp01(sm.currentIntensity));
            Vector2 pos = virtualArm.anchoredPosition;
            pos.y = y;
            virtualArm.anchoredPosition = pos;

            if (sm.state == SimulationGameManager.TrialState.Fired && targetFlashTimer > 0f)
            {
                float shake = Mathf.Sin(Time.time * 60f) * 4f * (targetFlashTimer / targetFlashDuration);
                pos.x = shake;
                virtualArm.anchoredPosition = pos;
            }
            else
            {
                pos.x = 0f;
                virtualArm.anchoredPosition = pos;
            }
        }

        if (target != null && targetFlashTimer > 0f)
        {
            targetFlashTimer -= Time.deltaTime;
            if (targetFlashTimer <= 0f)
            {
                target.color = targetIdleColor;
            }
        }

        if (screenFlash != null && flashTimer > 0f)
        {
            flashTimer -= Time.deltaTime;
            float a = Mathf.Clamp01(flashTimer / fireFlashDuration);
            var c = screenFlash.color;
            c.a = a * 0.6f;
            screenFlash.color = c;
            if (flashTimer <= 0f)
            {
                c.a = 0f;
                screenFlash.color = c;
            }
        }

        if (ringsPopup != null && ringsPopupTimer > 0f)
        {
            ringsPopupTimer -= Time.deltaTime;
            float t = 1f - Mathf.Clamp01(ringsPopupTimer / ringsPopupDuration);
            float scale = Mathf.Lerp(0.3f, 1.4f, Mathf.Min(1f, t * 3f));
            ringsPopup.transform.localScale = new Vector3(scale, scale, 1f);
            var c = ringsPopup.color;
            c.a = (ringsPopupTimer <= 0f) ? 0f : Mathf.Clamp01(ringsPopupTimer / (ringsPopupDuration * 0.7f));
            ringsPopup.color = c;
        }
    }

    void EnsureDebugHud()
    {
        if (!autoCreateDebugHudIfMissing) return;
        if (trialText != null && thresholdText != null && hitsText != null && stateText != null && scoreText != null && intensityText != null && lastShotText != null) return;

        return;
    }

    void OnStateChanged(SimulationGameManager.TrialState from, SimulationGameManager.TrialState to)
    {
        if (to == SimulationGameManager.TrialState.Fired)
        {
            hasShotResult = true;
        }

        if (to != SimulationGameManager.TrialState.Fired || hideLegacy2DVisuals) return;

        var sm = SimulationGameManager.Instance;
        if (sm == null) return;

        if (targetRings != null)
        {
            targetRings.Highlight(sm.lastRings, sm.lastWasHit);
        }
        else if (target != null)
        {
            targetFlashTimer = targetFlashDuration;
            target.color = sm.lastWasHit ? targetHitColor : targetMissColor;
        }

        if (screenFlash != null)
        {
            flashTimer = fireFlashDuration;
            Color c = sm.lastWasHit
                ? new Color(1f, 0.95f, 0.6f, 0.6f)
                : new Color(1f, 0.3f, 0.3f, 0.6f);
            screenFlash.color = c;
        }

        if (ringsPopup != null)
        {
            ringsPopupTimer = ringsPopupDuration;
            if (!sm.lastWasHit)
            {
                ringsPopup.text = "MISS";
                ringsPopup.color = ringsMissColor;
            }
            else
            {
                ringsPopup.text = $"{sm.lastRings}";
                if (sm.lastRings >= 9) ringsPopup.color = ringsGoldColor;
                else if (sm.lastRings >= 7) ringsPopup.color = ringsSilverColor;
                else ringsPopup.color = ringsBronzeColor;
            }
            ringsPopup.transform.localScale = Vector3.one * 0.3f;
        }
    }

    void ApplyModalityVisibility(Modality m)
    {
        bool showVisual = (m == Modality.Visual || m == Modality.Both) && !hideLegacy2DVisuals;

        if (intensityBarFill != null && intensityBarFill.transform.parent != null)
            intensityBarFill.transform.parent.gameObject.SetActive(showVisual);
        if (thresholdLine != null) thresholdLine.gameObject.SetActive(showVisual);
        if (virtualArm != null) virtualArm.gameObject.SetActive(showVisual);
        if (target != null) target.gameObject.SetActive(showVisual);
        if (screenFlash != null) screenFlash.gameObject.SetActive(showVisual);
        if (ringsPopup != null) ringsPopup.gameObject.SetActive(showVisual);
    }
}
