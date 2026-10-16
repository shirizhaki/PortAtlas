# Contributing

Use Xcode 26+ / the macOS 26 SDK. Use the local Swift package for model tests and the Xcode app target for UI development. Run `./Scripts/test.sh` and build the app before proposing a change.

Keep system discovery out of SwiftUI views. Add optional fields with an explicit meaning and source; do not infer transport speed, physical wiring, real consumption, or dock grouping from a name. Keep live display identity matching in memory only; never persist or log device serials.

Regression fixtures must be synthetic or fully sanitized. Never commit real IORegistry dumps or user settings. Keep any private observations in ignored `LocalCaptures/`.

Changes to physical mapping require hardware observations across protocols and reboot, described in the pull request. Changes to settings require a schema/version compatibility decision. Unknown and unsupported data should remain inspectable.

Use only public system APIs. Discuss missing observability before introducing new permissions, dependencies, helpers, or device control. PortAtlas is MIT licensed. Preserve its notice and the separate WhatPort MIT notice.
