# Third-party acknowledgements

PortAtlas adapts the read-only CC connection-state and USB-PD contract property parsing from [WhatPort](https://github.com/darrylmorley/whatport), commit `e672756`, by Darryl Morley, licensed under MIT. Adaptations live in `PowerDiscovery.swift`, `PowerOutputDiscovery.swift`, `SMCInputReader.swift`, and `TransportDiscovery.swift` in `Sources/PortAtlasHardware/`. The copyright and full license are preserved in `ThirdPartyNotices/WhatPort-LICENSE.txt`.

The CCReader/ChargerReader, ThunderboltReader and system-input portion of SMCPowerReader approaches are used. The SMC adapter reads DC-input keys PDTR, VD0R and ID0R and optional output rails DxJV/DxJI with DxUI identities through an unprivileged AppleSMC client. Output joins require a unique HPM controller UUID; D-channel indices are never used as physical port numbers. There is no write operation. PortAtlas does not include WhatPort Pro, its UI, licensing, updater or network services. A highest advertised PDO is retained only as adapter capability, never as a selected contract. Source routing keeps ambiguous inputs unassigned. A lone active MagSafe connection may be inferred only when every detected USB-C connector explicitly reports inactive; that inference is labeled in the UI.

The optional active-cable identity parser also adapts CCReader's SOP' metadata
rules: cable product type and PD specification revision. No cable speed/current
rating is inferred from these fields. The bundled MIT notice covers this adaptation.


Outgoing-power readings adapt the WhatPort PowerReader and SMCPowerReader approaches under the same MIT notice. AppleSmartBattery.PowerOutDetails uses milliwatts, millivolts and milliamps, validated against V × I. Its explicit PortIndex joins only a unique active host USB-C PortNumber. Optional live SMC readings replace firmware-batched readings only with a unique UUID match, including suppressing stale positive reports when the live output is zero. No device battery state, negotiated USB-PD protocol, VConn power or power beyond a dock is inferred from these measurements.

PortAtlas itself uses the root MIT `LICENSE` (2026 PortAtlas contributors). Both the root license and the unchanged WhatPort notice are bundled by the app packaging script and Xcode resource phase. Neither notice replaces the other.
