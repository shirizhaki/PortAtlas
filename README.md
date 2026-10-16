# PortAtlas

A native macOS app that maps the devices connected to your Mac: USB, Thunderbolt/USB4, storage, external displays, and available power readings.

**Early 0.1.0 preview · Apple Silicon · macOS 14 or newer.** PortAtlas reads local hardware information. It has no network services or analytics. Hardware and macOS versions expose different amounts of information; missing or ambiguous readings stay unavailable.

## The map

- **Physical view** groups connections by the Mac's physical sockets, with downstream accessories and optional dock-component overrides.
- **Logical view** preserves the reported device ancestry. Changing physical presentation never changes this topology.
- Both views support pan, zoom, Fit All, Focus Selection, and an inspector. Click empty map space or press Escape to close details.
- Data, display, incoming power, and outgoing power have distinct colors and icons. Power tracks are thicker; animation indicates direction rather than measured traffic.
- Storage cards show mounted capacity when the device-to-volume association is verified.
- A uniquely matched display can follow its HDMI or DisplayPort route, including through a Thunderbolt dock. Actual signal resolution is separate from macOS scaling. Reported selected VRR ranges, nominal refresh, available macOS desktop modes, and validated EDID details appear in the inspector. Instantaneous HDMI refresh and application FPS are not measured.
- Optional live Mac-input and USB-C-output readings are separate from USB-PD contracts and adapter ratings. Output describes the Mac connector, not an accessory's battery state or consumption beyond a dock.
- Choose Follow System, Light, or Dark in Settings. Floating controls use Liquid Glass on macOS 26+, with standard material fallbacks. Cards use standard materials, and accessibility contrast, transparency, and motion settings are respected.

## Match physical ports

Hardware discovery does not depend on a Mac model list. However, a hardware connector number does **not** universally identify its left/right/front/back location.

1. Click **Match ports** above the map or in **PortAtlas → Settings…** (⌘,).
2. Connect one recognizable USB device directly to a Mac socket. A unique new host connection is suggested; if several devices are connected, choose the correct one.
3. Confirm the side and port name, then choose **Save position**. Repeat by moving the device to the next socket.
4. Add sockets in physical order. On laptop sides, start closest to the screen. On desktop front/back panels, start at the left while looking directly at that panel. Use Settings arrows to adjust order afterward.
5. Recheck after reconnecting, restarting, and macOS upgrades. Saved registry paths are local associations; their stability across OS changes is not guaranteed.

USB 2 and USB 3 branches sharing the same validated connector follow one assignment. A previously created empty position can be reused. The guide never chooses a physical side or overwrites a different occupied socket automatically.

MagSafe appears only when reported, on the left nearest the hinge. A single built-in HDMI connector appears automatically, with a default right-side laptop or rear desktop position that Settings can adjust. Explicitly reported built-in USB-A IOPorts can be matched too. USB-A discovery on desktop hardware still needs validation; internal USB branches and dock sockets are not guessed to be Mac sockets. Missing connector evidence leaves devices unmapped and available in Logical view.

## Dock components

Use a component's inspector or context menu to choose **Automatic**, **Dock component**, or **Separate accessory**. Choices are saved independently of port positions and retained for the same device at the same connection route. A different route can require another choice. Automatic grouping is a presentation hint, not proof that an Ethernet adapter or receiver is physically built into a dock.

## Accuracy and hardware coverage

- USB device rates describe enumeration, not benchmark throughput. Hardware maximum Thunderbolt/USB4 rates and positively reported USB/DisplayPort protocols supply port support labels. An advanced manual override is optional. The small model-reference list supplies specification links, not runtime port allocation.
- HDMI presence is detected without a model database. The port's maximum HDMI version/bandwidth is unavailable unless independently reported. Internal DisplayPort lane capacity is not presented as HDMI cable bandwidth.
- EDID describes the display. Decoded detailed timings are a subset of its advertised modes. Available macOS modes can include scaled render sizes and do not establish the port's maximum capability.
- Display matching requires unique identity and route evidence. Identical displays, virtual screens, or missing controller properties can leave readings or routes unavailable.
- Incoming-power routing is an explicitly labeled inference from a unique selected contract or restricted MagSafe evidence. Contract limits are not current draw. Optional read-only SMC telemetry and firmware readings vary across hardware; zero, missing, stale, and ambiguous readings are kept distinct.
- Built-in SD readers and built-in Ethernet ports are not yet separate physical sockets in the map. Connected Ethernet accessories can expose link information.
- Initial hands-on coverage is one Apple Silicon MacBook Pro with USB storage, a Thunderbolt dock, displays, and charging. Automated fixtures cover additional topologies, but they cannot establish support across all Macs. See the [hardware validation checklist](Docs/HardwareValidation.md).

The development app is unsandboxed. Discovery uses public IOKit entry points and optional driver properties, including an unprivileged read-only AppleSMC client. It never resets or writes devices. App Store sandbox compatibility and a notarized distribution build have not been established.

## Build locally

**Build tools:** Xcode 26+ with the macOS 26 SDK, or matching Command Line Tools for the Swift-package build. The runtime minimum remains macOS 14. Full Xcode is required for the `.xcodeproj` target. No external packages are downloaded.

Open `PortAtlas.xcodeproj`, select the **PortAtlas** scheme, and Run. Local signing is disabled. Alternatively:

```sh
./Scripts/check-toolchain.sh
swift build
./Scripts/test.sh
swift run PortAtlas
```

To build a Finder-launchable local app:

```sh
./Scripts/build-app.sh
open build/PortAtlas.app
```

This packages both licenses, strips debug symbols, and signs ad hoc. It does not publish, notarize, or upload anything. The optional GitHub workflow builds/tests the package and Xcode target using a macOS 26 runner; it has no release or publishing step.

## Local settings and a fresh start

- Port names and assignments: `~/Library/Application Support/PortAtlas/ports.json`
- Dock presentation choices: `~/Library/Application Support/PortAtlas/presentation.json`
- Appearance: app-local UserDefaults.

To test fresh **port matching**, quit the app and move only `ports.json` to a private backup outside the checkout. Relaunch to see hardware discovery without saved positions. Keep `presentation.json` to retain dock choices. Restore the backed-up layout while the app is closed; back up any new layout first. Replacing the app bundle alone does not clear settings. A truly new-user test can use a separate macOS user account, without disturbing existing preferences.

EDID, display identities, power graphs, and hardware snapshots are session-only. No real hardware captures belong in the repository. Keep screenshots of personal volume/device names private.

## Sharing source

```sh
python3 Scripts/package-source.py
```

Before publishing Git history, run `python3 Scripts/package-source.py --check-git-history`.
This also requires the neutral project identity in author and committer metadata
for every commit reachable from HEAD. The project's initial publication uses a
reserved, non-deliverable `.invalid` address, rather than an account email or a
GitHub user-specific no-reply address. Inspect the actual uploaded history before
making a repository public; hosting tools may substitute account identities.

This creates `build/PortAtlas-source.zip` from Git-visible files and rejects common personal-path, credential, settings, and capture patterns, including sensitive files already tracked before ignore rules were added. It is a limited local check, not a guarantee; inspect the result before sharing. `.gitignore` excludes build outputs, debug symbols, captures, local settings, editor state, and common credential files. Do not upload the entire working folder or local backups.

## Project layout

```text
Sources/PortAtlasCore/        Models, topology projections, matching, persistence
Sources/PortAtlasHardware/    Read-only discovery and telemetry
Sources/PortAtlasApp/         SwiftUI app and presentation
Sources/PortAtlasDiagnostics/ Read-only diagnostics
Tests/PortAtlasCoreTests/     Synthetic fixtures and regression tests
Docs/                        Architecture, evidence, hardware validation
Scripts/                     Local build, tests, source packaging
PortAtlas.xcodeproj/          Native app target using local package libraries
```

## Contributors

- [@shirizhaki](https://github.com/shirizhaki) — Project creator, product direction, design, and hardware testing.
- [OpenAI Codex](https://openai.com/codex/) — AI-assisted implementation, debugging, testing, and release preparation.

## License and acknowledgements

PortAtlas is available under the [MIT License](LICENSE), copyright 2026 PortAtlas contributors. Preserve its copyright and permission notice when redistributing copies or substantial portions.

Selected discovery and power-reading approaches are adapted from **WhatPort**, copyright 2025 Darryl Morley, also under MIT. Its original notice is retained verbatim in [ThirdPartyNotices/WhatPort-LICENSE.txt](ThirdPartyNotices/WhatPort-LICENSE.txt) and included in the app. Preserve both notices for distributions containing those adaptations. See [adaptation details](Docs/ThirdParty.md).

See also [architecture](Docs/Architecture.md), [capability evidence](Docs/PortCapabilities.md), and [contributing](CONTRIBUTING.md).
