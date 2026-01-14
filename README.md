[![CI](https://github.com/celikhakan41/Unfollowers/actions/workflows/ci.yml/badge.svg)](https://github.com/celikhakan41/Unfollowers/actions/workflows/ci.yml)

# Unfollowers

An example iOS app built with SwiftUI, focused on analyzing Instagram export data to identify accounts that unfollowed you.

## Table of Contents
- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [Commands](#commands)
- [Simulator & UDID](#simulator--udid)
- [Project Structure](#project-structure)
- [Tests](#tests)
- [Scripts](#scripts)
- [Version Control Hygiene](#version-control-hygiene)
- [CI / Automation Notes](#ci--automation-notes)
- [Troubleshooting](#troubleshooting)

## Overview
This repository follows a clean, reproducible iOS project layout with Makefile-driven commands and CI-friendly conventions. All build outputs, logs, and machine-specific files are excluded via `.gitignore`.

## Features
- SwiftUI-based UI
- File picker (import Instagram export)
- JSON parsing (with example datasets)
- Xcode test plan for unit and UI tests

## Requirements
- macOS with Xcode (15 or newer recommended)
- iOS Simulator runtime (installed with Xcode)
- Internet access to resolve Swift Package Manager dependencies

## Getting Started
The following commands are provided via the Makefile:

```bash
# Build (includes fetching SPM dependencies)
make build

# Run unit tests
make test

# Build + install to simulator + launch
make

# Clean (including DerivedData/.build)
make clean

# List available simulators (find UDIDs)
make list-sims
```

Notes:
- `make test` and `make` will attempt to boot a simulator. If your UDID/destination is different, update it (see below).
- SPM dependencies cannot be resolved without internet access.

## Getting Instagram Export (ZIP, JSON)
Steps to obtain your Instagram data export in JSON format:
1. Open Instagram (mobile app or web) and go to Settings → Privacy and security (web) or Your activity (mobile).
2. Find “Download your information” (or “Download data”).
3. Request a download in JSON format and include relevant date range (or “All time”).
4. When you receive the email from Instagram, download the ZIP to your Mac.
5. Use the app’s file picker to select the ZIP. The app works fully offline; it does not require login or use any Instagram API.

Optional: Add screenshots under `docs/images/` (see `docs/images/README.md`).

## Simulator & UDID
Key Makefile variables:

- `SCHEME`: Unfollowers
- `SIM_UDID`: UDID of the target simulator for running tests and the app
- `DESTINATION`: `platform=iOS Simulator,id=$(SIM_UDID)`

Find UDID and override temporarily:

```bash
make list-sims
# Copy the UDID of a suitable device
SIM_UDID=<UDID> make test
```

To make it permanent, update `SIM_UDID` in the `Makefile`.

## Project Structure
```text
Unfollowers/
├─ Unfollowers.xcodeproj/
│  ├─ project.pbxproj
│  ├─ project.xcworkspace/
│  └─ xcshareddata/
├─ Unfollowers/
│  ├─ Assets.xcassets/
│  ├─ Localization/
│  ├─ Resources/
│  ├─ UnfollowersApp.swift
│  ├─ ContentView.swift
│  ├─ DocumentPicker.swift
│  ├─ ShareSheet.swift
│  └─ InstagramJSONParser.swift
├─ UnfollowersTests/
│  ├─ UnfollowersTests.swift
│  ├─ InstagramJSONParserGoldenTests.swift
│  └─ Fixtures/
│     ├─ Senaryo A.zip
│     ├─ Senaryo B.zip
│     ├─ Senaryo C.zip
│     └─ instagram_export_test_all0_appformat_fixed.zip
├─ UnfollowersUITests/
│  ├─ UnfollowersUITests.swift
│  └─ UnfollowersUITestsLaunchTests.swift
├─ Unfollowers.xctestplan
├─ scripts/
│  └─ generate_appicon.swift
├─ Makefile
├─ AGENTS.md
├─ CODING_RULES.md
└─ .gitignore
```

> Note: Build outputs (`.build/`, `DerivedData/`), temporary folders, and logs are not included in the repository; they are excluded via `.gitignore`.

## Tests
- Unit and UI tests are executed via the Xcode test plan (`Unfollowers.xctestplan`).
- Test fixtures (ZIP archives) live under `UnfollowersTests/Fixtures/`.
- Run:
  ```bash
  make test
  ```

## Scripts
- `scripts/generate_appicon.swift`: Generates a 1024x1024 example app icon and writes it to `Unfollowers/Assets.xcassets/AppIcon.appiconset/`.
  ```bash
  swift scripts/generate_appicon.swift
  ```

## Version Control Hygiene
Never commit the following (with reasons):
- Build/derived outputs: `.build/`, `DerivedData/`, `*.xcarchive`, `*.xcresult` — machine-specific and reproducible on CI.
- Logs/temporary files: `.logs/`, `.tmp/`, `*.log`, `*.exit` — noisy and non-deterministic.
- Xcode user data: `xcuserdata/`, `*.xcuserstate` — developer-specific settings causing unnecessary diffs.
- OS/IDE cruft: `.DS_Store`, `.idea/`, `.vscode/` — unrelated to the build.

See the root `.gitignore` for the full list.

## CI / Automation Notes
- Use a macOS runner (e.g., GitHub Actions).
- Steps: Install Xcode → optionally cache SPM → `make build` → `make test`.
- Shared schemes under `xcshareddata/` are included in version control for CI.

## Troubleshooting
- "Could not resolve package dependencies": SPM requires internet access to fetch packages. Verify network in local/CI environments.
- "Unable to find application named 'Simulator'": The CLI cannot access the Simulator app. Ensure Xcode Command Line Tools and iOS Simulator components are installed; use `make list-sims` to verify devices and update `SIM_UDID`.
- UDID-related issues: Use `make list-sims` to find a suitable device, try `SIM_UDID=<UDID> make test`, or update the `Makefile`.
