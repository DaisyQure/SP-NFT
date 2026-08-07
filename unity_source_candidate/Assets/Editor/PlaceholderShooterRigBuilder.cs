#if UNITY_EDITOR
using System;
using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;
using TMPro;

public static class PlaceholderShooterRigBuilder
{
    const string ScenePath = "Assets/Scenes/Game_Simulation3D.unity";
    static readonly string[] PublicSupportScenes = {
        "Assets/Scenes/_Bootstrap.unity",
        "Assets/Scenes/MainMenu.unity"
    };
    const string PrefabDirectory = "Assets/SPNFT/Placeholders";
    const string PrefabPath = PrefabDirectory + "/SPNFT_PlaceholderShooterRig.prefab";
    const string PublicFontPath = "Assets/TextMesh Pro/Resources/Fonts & Materials/LiberationSans SDF.asset";

    public static void ReplaceAndValidate()
    {
        EnsureDirectory(PrefabDirectory);
        GameObject prefab = BuildPrefab();
        if (prefab == null) throw new InvalidOperationException("Could not create placeholder shooter prefab.");

        Scene scene = EditorSceneManager.OpenScene(ScenePath, OpenSceneMode.Single);
        Camera sceneCamera = FindSceneComponent<Camera>(scene, component => component.CompareTag("MainCamera"));
        if (sceneCamera == null) sceneCamera = FindSceneComponent<Camera>(scene, component => true);
        if (sceneCamera == null) throw new InvalidOperationException("Simulation scene has no camera.");

        Transform shooterRig = sceneCamera.transform.Find("Simulation3D_ShooterRig");
        if (shooterRig == null) throw new InvalidOperationException("Simulation3D_ShooterRig is missing under the scene camera.");

        for (int i = shooterRig.childCount - 1; i >= 0; i--)
        {
            Transform child = shooterRig.GetChild(i);
            if (child.name == "Rifle_WeaponObject" || child.name == "ShoulderPivot" || child.name == "PlaceholderKeyLight")
            {
                UnityEngine.Object.DestroyImmediate(child.gameObject);
            }
        }

        GameObject instance = (GameObject)PrefabUtility.InstantiatePrefab(prefab, scene);
        instance.name = "Rifle_WeaponObject";
        instance.transform.SetParent(shooterRig, false);
        instance.transform.localPosition = new Vector3(0.28f, -0.24f, 0.58f);
        instance.transform.localRotation = Quaternion.Euler(1.5f, -1f, 0f);

        Transform weapon = FindChildRecursive(instance.transform, "Weapon");
        Transform aimPoint = FindChildRecursive(instance.transform, "AimPoint");
        Transform firePoint = FindChildRecursive(instance.transform, "FirePoint");
        Transform swayPivot = FindChildRecursive(instance.transform, "SwayPivot");

        Simulation3DView view = FindSceneComponent<Simulation3DView>(scene, component => true);
        Simulation3DTargetFeedback feedback = FindSceneComponent<Simulation3DTargetFeedback>(scene, component => true);
        if (view == null || feedback == null) throw new InvalidOperationException("Simulation3D presentation scripts are missing.");

        Transform targetAimPoint = FindChildRecursive(feedback.transform, "TargetAimPoint");
        if (targetAimPoint == null) throw new InvalidOperationException("TargetAimPoint is missing.");

        view.sceneCamera = sceneCamera;
        view.targetFeedback = feedback;
        view.targetAimPoint = targetAimPoint;
        view.shoulderPivot = null;
        view.forearmPivot = null;
        view.gunRoot = null;
        view.muzzlePoint = firePoint;
        view.rifleRigRoot = instance.transform;
        view.rifleWeapon = weapon;
        view.rifleAimPoint = aimPoint;
        view.rifleFirePoint = firePoint;
        view.rifleSwayPivot = swayPivot;
        view.rifleFireAudioSource = null;
        view.rifleFireClip = null;
        view.muzzleFlashRenderer = null;
        view.muzzleFlashLight = CreateMuzzleLight(firePoint);

        RemoveRestrictedSceneDependencies(scene);

        EditorUtility.SetDirty(view);
        EditorUtility.SetDirty(feedback);
        EditorSceneManager.MarkSceneDirty(scene);
        EditorSceneManager.SaveScene(scene, ScenePath);
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();

        ValidateScene(scene);
        SanitizePublicSupportScenes();
        Debug.Log("[PlaceholderRig] PASS: primitive-only rig created, scene replaced, and interfaces rebound.");
    }

    public static void ValidatePublicScene()
    {
        Scene scene = EditorSceneManager.OpenScene(ScenePath, OpenSceneMode.Single);
        ValidateScene(scene);
        Debug.Log("[PlaceholderRig] PASS: public simulation scene interfaces and dependencies validated.");
    }

    static GameObject BuildPrefab()
    {
        GameObject root = new GameObject("Rifle_WeaponObject");
        try
        {
            GameObject sway = new GameObject("SwayPivot");
            sway.transform.SetParent(root.transform, false);

            GameObject weapon = new GameObject("Weapon");
            weapon.transform.SetParent(sway.transform, false);

            Material gun = CreateMaterial("PlaceholderGun", new Color(0.055f, 0.07f, 0.075f, 1f), 0.35f, 0.15f);
            Material metal = CreateMaterial("PlaceholderMetal", new Color(0.15f, 0.18f, 0.19f, 1f), 0.75f, 0.35f);
            Material grip = CreateMaterial("PlaceholderGrip", new Color(0.12f, 0.095f, 0.065f, 1f), 0.15f, 0.05f);
            Material skin = CreateMaterial("PlaceholderSkin", new Color(0.58f, 0.35f, 0.24f, 1f), 0.05f, 0f);
            Material sleeve = CreateMaterial("PlaceholderSleeve", new Color(0.10f, 0.24f, 0.22f, 1f), 0.1f, 0f);

            CreatePrimitive(PrimitiveType.Cube, "Receiver", weapon.transform, new Vector3(0f, 0f, 0.40f), Vector3.zero, new Vector3(0.18f, 0.15f, 0.72f), gun);
            CreatePrimitive(PrimitiveType.Cylinder, "Barrel", weapon.transform, new Vector3(0f, 0.015f, 0.96f), new Vector3(90f, 0f, 0f), new Vector3(0.055f, 0.38f, 0.055f), metal);
            CreatePrimitive(PrimitiveType.Cube, "Stock", weapon.transform, new Vector3(0f, -0.01f, -0.08f), new Vector3(-4f, 0f, 0f), new Vector3(0.16f, 0.20f, 0.35f), grip);
            CreatePrimitive(PrimitiveType.Cube, "ForeGrip", weapon.transform, new Vector3(0f, -0.13f, 0.56f), new Vector3(-12f, 0f, 0f), new Vector3(0.10f, 0.26f, 0.13f), grip);
            CreatePrimitive(PrimitiveType.Cube, "SightRail", weapon.transform, new Vector3(0f, 0.11f, 0.40f), Vector3.zero, new Vector3(0.08f, 0.035f, 0.44f), metal);
            CreatePrimitive(PrimitiveType.Cylinder, "FrontSight", weapon.transform, new Vector3(0f, 0.15f, 0.78f), Vector3.zero, new Vector3(0.025f, 0.045f, 0.025f), metal);

            GameObject arms = new GameObject("Arms");
            arms.transform.SetParent(sway.transform, false);
            CreatePrimitive(PrimitiveType.Capsule, "RightForearm", arms.transform, new Vector3(0.13f, -0.23f, 0.17f), new Vector3(72f, 4f, -12f), new Vector3(0.13f, 0.34f, 0.13f), sleeve);
            CreatePrimitive(PrimitiveType.Capsule, "RightHand", arms.transform, new Vector3(0.07f, -0.10f, 0.40f), new Vector3(77f, 2f, -8f), new Vector3(0.11f, 0.18f, 0.10f), skin);
            CreatePrimitive(PrimitiveType.Capsule, "LeftForearm", arms.transform, new Vector3(-0.23f, -0.27f, 0.49f), new Vector3(62f, -16f, 20f), new Vector3(0.13f, 0.34f, 0.13f), sleeve);
            CreatePrimitive(PrimitiveType.Capsule, "LeftHand", arms.transform, new Vector3(-0.11f, -0.13f, 0.64f), new Vector3(78f, -5f, 16f), new Vector3(0.11f, 0.17f, 0.10f), skin);

            CreateMarker("AimPoint", sway.transform, new Vector3(0f, 0.105f, 0.78f));
            CreateMarker("FirePoint", sway.transform, new Vector3(0f, 0.015f, 1.36f));

            GameObject saved = PrefabUtility.SaveAsPrefabAsset(root, PrefabPath);
            return saved;
        }
        finally
        {
            UnityEngine.Object.DestroyImmediate(root);
        }
    }

    static Light CreateMuzzleLight(Transform firePoint)
    {
        Transform existing = firePoint.Find("MuzzleFlashLight");
        if (existing != null) UnityEngine.Object.DestroyImmediate(existing.gameObject);
        GameObject lightObject = new GameObject("MuzzleFlashLight");
        lightObject.transform.SetParent(firePoint, false);
        Light light = lightObject.AddComponent<Light>();
        light.type = LightType.Point;
        light.color = new Color(1f, 0.72f, 0.25f, 1f);
        light.range = 3f;
        light.intensity = 0f;
        light.shadows = LightShadows.None;
        return light;
    }

    static GameObject CreatePrimitive(PrimitiveType type, string name, Transform parent, Vector3 position, Vector3 euler, Vector3 scale, Material material)
    {
        GameObject item = GameObject.CreatePrimitive(type);
        item.name = name;
        item.transform.SetParent(parent, false);
        item.transform.localPosition = position;
        item.transform.localRotation = Quaternion.Euler(euler);
        item.transform.localScale = scale;
        Collider collider = item.GetComponent<Collider>();
        if (collider != null) UnityEngine.Object.DestroyImmediate(collider);
        Renderer renderer = item.GetComponent<Renderer>();
        if (renderer != null) renderer.sharedMaterial = material;
        return item;
    }

    static void CreateMarker(string name, Transform parent, Vector3 position)
    {
        GameObject marker = new GameObject(name);
        marker.transform.SetParent(parent, false);
        marker.transform.localPosition = position;
    }

    static Material CreateMaterial(string name, Color color, float smoothness, float metallic)
    {
        string path = PrefabDirectory + "/" + name + ".mat";
        Material material = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (material == null)
        {
            Shader shader = Shader.Find("Universal Render Pipeline/Lit");
            if (shader == null) shader = Shader.Find("Standard");
            material = new Material(shader) { name = name };
            AssetDatabase.CreateAsset(material, path);
        }
        if (material.HasProperty("_BaseColor")) material.SetColor("_BaseColor", color);
        if (material.HasProperty("_Color")) material.SetColor("_Color", color);
        if (material.HasProperty("_Smoothness")) material.SetFloat("_Smoothness", smoothness);
        if (material.HasProperty("_Metallic")) material.SetFloat("_Metallic", metallic);
        EditorUtility.SetDirty(material);
        return material;
    }

    static void ValidateScene(Scene scene)
    {
        Camera camera = FindSceneComponent<Camera>(scene, component => component.CompareTag("MainCamera"));
        if (camera == null) camera = FindSceneComponent<Camera>(scene, component => true);
        Simulation3DView view = FindSceneComponent<Simulation3DView>(scene, component => true);
        Simulation3DTargetFeedback feedback = FindSceneComponent<Simulation3DTargetFeedback>(scene, component => true);
        if (camera == null || view == null || feedback == null) throw new InvalidOperationException("Required simulation components are missing.");

        Transform shooter = camera.transform.Find("Simulation3D_ShooterRig");
        Transform rifle = shooter != null ? FindChildRecursive(shooter, "Rifle_WeaponObject") : null;
        Transform weapon = rifle != null ? FindChildRecursive(rifle, "Weapon") : null;
        Transform aim = rifle != null ? FindChildRecursive(rifle, "AimPoint") : null;
        Transform fire = rifle != null ? FindChildRecursive(rifle, "FirePoint") : null;
        Transform sway = rifle != null ? FindChildRecursive(rifle, "SwayPivot") : null;
        Transform target = FindChildRecursive(feedback.transform, "TargetAimPoint");
        if (shooter == null || rifle == null || weapon == null || aim == null || fire == null || sway == null || target == null)
            throw new InvalidOperationException("One or more required placeholder interfaces are missing.");
        if (view.rifleRigRoot != rifle || view.rifleWeapon != weapon || view.rifleAimPoint != aim || view.rifleFirePoint != fire || view.rifleSwayPivot != sway || view.targetAimPoint != target || view.targetFeedback != feedback)
            throw new InvalidOperationException("Simulation3DView references are not bound to the placeholder rig.");

        string yaml = File.ReadAllText(ScenePath);
        string[] forbidden = {
            "5ca5d64a3d7b321408787460766590cd",
            "ec5cd49f8987a494d96bf93339c8bfb3",
            "49e68d59c48b4754d9470301ae27d746",
            "cf2bdf6730151734c8b28c0ad057cd0b",
            "b10706aeac9cac64788c134c6641ea79",
            "Assets/Cowsins"
        };
        foreach (string token in forbidden)
        {
            if (yaml.IndexOf(token, StringComparison.OrdinalIgnoreCase) >= 0)
                throw new InvalidOperationException("Restricted dependency remains in scene: " + token);
        }
    }

    static void RemoveRestrictedSceneDependencies(Scene scene)
    {
        RenderSettings.skybox = null;
        Material placeholderMetal = AssetDatabase.LoadAssetAtPath<Material>(PrefabDirectory + "/PlaceholderMetal.mat");
        TMP_FontAsset publicFont = AssetDatabase.LoadAssetAtPath<TMP_FontAsset>(PublicFontPath);
        if (publicFont == null) throw new InvalidOperationException("LiberationSans SDF from TMP Essentials is missing.");

        foreach (GameObject root in scene.GetRootGameObjects())
        {
            foreach (Renderer renderer in root.GetComponentsInChildren<Renderer>(true))
            {
                Material[] materials = renderer.sharedMaterials;
                bool changed = false;
                for (int i = 0; i < materials.Length; i++)
                {
                    string path = AssetDatabase.GetAssetPath(materials[i]);
                    if (path.StartsWith("Assets/Cowsins/", StringComparison.OrdinalIgnoreCase))
                    {
                        materials[i] = placeholderMetal;
                        changed = true;
                    }
                }
                if (changed) renderer.sharedMaterials = materials;
            }

            foreach (TMP_Text text in root.GetComponentsInChildren<TMP_Text>(true))
            {
                string path = AssetDatabase.GetAssetPath(text.font);
                if (path.StartsWith("Assets/Fonts/", StringComparison.OrdinalIgnoreCase))
                {
                    text.font = publicFont;
                    text.fontSharedMaterial = publicFont.material;
                    EditorUtility.SetDirty(text);
                }
            }
        }
    }

    static void SanitizePublicSupportScenes()
    {
        TMP_FontAsset publicFont = AssetDatabase.LoadAssetAtPath<TMP_FontAsset>(PublicFontPath);
        if (publicFont == null) throw new InvalidOperationException("LiberationSans SDF from TMP Essentials is missing.");

        foreach (string scenePath in PublicSupportScenes)
        {
            Scene scene = EditorSceneManager.OpenScene(scenePath, OpenSceneMode.Single);
            RenderSettings.skybox = null;
            foreach (GameObject root in scene.GetRootGameObjects())
            {
                foreach (TMP_Text text in root.GetComponentsInChildren<TMP_Text>(true))
                {
                    string path = AssetDatabase.GetAssetPath(text.font);
                    if (path.StartsWith("Assets/Fonts/", StringComparison.OrdinalIgnoreCase))
                    {
                        SerializedObject serializedText = new SerializedObject(text);
                        SerializedProperty fontAsset = serializedText.FindProperty("m_fontAsset");
                        SerializedProperty sharedMaterial = serializedText.FindProperty("m_sharedMaterial");
                        if (fontAsset != null) fontAsset.objectReferenceValue = publicFont;
                        if (sharedMaterial != null) sharedMaterial.objectReferenceValue = publicFont.material;
                        serializedText.ApplyModifiedPropertiesWithoutUndo();
                        EditorUtility.SetDirty(text);
                    }
                }

                foreach (UnityEngine.UI.Image image in root.GetComponentsInChildren<UnityEngine.UI.Image>(true))
                {
                    string path = AssetDatabase.GetAssetPath(image.sprite);
                    if (!string.IsNullOrEmpty(path) && path.StartsWith("Assets/", StringComparison.OrdinalIgnoreCase))
                    {
                        image.sprite = null;
                        EditorUtility.SetDirty(image);
                    }
                }
            }
            EditorSceneManager.MarkSceneDirty(scene);
            EditorSceneManager.SaveScene(scene, scenePath);

            string yaml = File.ReadAllText(scenePath);
            if (yaml.IndexOf("b10706aeac9cac64788c134c6641ea79", StringComparison.OrdinalIgnoreCase) >= 0)
                throw new InvalidOperationException("Restricted local font remains in support scene: " + scenePath);
        }
        AssetDatabase.SaveAssets();
    }

    static T FindSceneComponent<T>(Scene scene, Predicate<T> predicate) where T : Component
    {
        foreach (GameObject root in scene.GetRootGameObjects())
        {
            foreach (T component in root.GetComponentsInChildren<T>(true))
            {
                if (predicate(component)) return component;
            }
        }
        return null;
    }

    static Transform FindChildRecursive(Transform root, string childName)
    {
        if (root == null) return null;
        if (root.name == childName) return root;
        for (int i = 0; i < root.childCount; i++)
        {
            Transform match = FindChildRecursive(root.GetChild(i), childName);
            if (match != null) return match;
        }
        return null;
    }

    static void EnsureDirectory(string path)
    {
        string[] parts = path.Split('/');
        string current = parts[0];
        for (int i = 1; i < parts.Length; i++)
        {
            string next = current + "/" + parts[i];
            if (!AssetDatabase.IsValidFolder(next)) AssetDatabase.CreateFolder(current, parts[i]);
            current = next;
        }
    }
}
#endif
