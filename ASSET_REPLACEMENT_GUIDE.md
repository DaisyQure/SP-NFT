# Unity Asset Replacement Guide

The SP-NFT software logic is separated from the visual asset layer. A clean public release may replace restricted local demonstration assets with author-created or redistributable placeholders.

## Required object interfaces

The simulation scene should retain these object roles, even when the visual meshes are replaced:

- `Simulation3D_ShooterRig`: parent transform for the first-person presentation.
- `Rifle_WeaponObject`: parent transform for the weapon placeholder.
- `Weapon`: visible weapon mesh or a primitive placeholder.
- `AimPoint`: transform used for aiming alignment.
- `FirePoint`: transform used for muzzle effects and firing events.
- `SwayPivot`: transform used for feedback-driven sway and recoil.
- `TargetAimPoint`: target transform used by aim assistance.

## Redistributable placeholder included in this release

`Assets/SPNFT/Placeholders/SPNFT_PlaceholderShooterRig.prefab` contains a primitive-only rifle assembled from Cubes and Cylinders and two arms assembled from Capsules. Its materials contain only scalar colors and Unity URP shader parameters. No external mesh, texture, animation, or audio is required. The exact appearance is not part of the software validation claim.

## Replacement procedure

1. Open the project in Unity 2022.3.62f3c1.
2. Run `PlaceholderShooterRigBuilder.ReplaceAndValidate` if the placeholder must be regenerated.
3. Open `Assets/Scenes/Game_Simulation3D.unity` and confirm the required object names.
4. Run `Week2SmokePlayerBuild.BuildWindowsSmokePlayer`.
5. Start the player with `-spnftAutoScene simulation -spnftQuitOnSessionStop -spnftSmokeProbe` while the MATLAB smoke server is listening.
6. Confirm phase ACK, session-stop ACK, feedback-driven motion, target response, and report generation.

## Release boundary

Do not copy local rifle, arm, Microsoft font, audio, texture, or model files into the public repository. The public simulation scene uses the primitive placeholder, Liberation Sans under SIL OFL, and silent firing by design.
