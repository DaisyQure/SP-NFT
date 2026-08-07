# Release Checklist

## Code and data

- [x] MATLAB core code is present and does not contain machine-specific paths.
- [x] Unity project-specific scripts are present.
- [x] Four anonymous simulated-input example sessions pass the file and ACK checks.
- [x] Week 2 aggregate summary is clearly separated from the four example sessions.
- [x] Figure-generation scripts run from the public package.

## Unity assets

- [x] Restricted rifle and arm assets are removed or replaced with legal placeholders.
- [x] Fonts, audio, textures, models, and packages have redistribution rights documented.
- [x] `ASSET_REPLACEMENT_GUIDE.md` matches the final scene object names.
- [x] A clean Unity checkout can open the public scene without missing required references.
- [x] A public smoke build completes from a clean Unity project copy.

## Repository metadata

- [x] Add the MIT `LICENSE` for original SP-NFT code.
- [x] Add third-party notices where required.
- [ ] Add a version tag, for example `v0.1.0`.
- [ ] Add a public repository URL to the manuscript.
- [ ] Add an archive DOI if the repository is archived.

## Manuscript

- [ ] Replace `[REPOSITORY_URL_TO_BE_ADDED]`.
- [ ] Replace `[RELEASE_TAG_TO_BE_ADDED]`.
- [ ] Replace `[LICENSE_TO_BE_CONFIRMED]`.
- [ ] Replace `[ARCHIVE_DOI_TO_BE_ADDED]` when applicable.
- [ ] Keep the simulated-input and software-proof-of-function boundaries explicit.
