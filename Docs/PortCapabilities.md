# Port capability evidence

Capability is nominal socket support, separate from a connected USB device’s negotiated link rate. A USB 2 device on a Thunderbolt 5 socket still has a USB 2 link. Neither a device speed nor the USB-C connector shape proves Thunderbolt support.

The optional reference profiles contain only models whose USB-C ports have uniform capabilities. Runtime automatic labels do not use this model list. Verified against [Apple’s model identifier and Thunderbolt generation listing](https://support.apple.com/en-us/108052) on October 11, 2026:

| Model identifiers | Automatic capability |
| --- | --- |
| Mac16,1; Mac17,2; Mac15,6–Mac15,11 | Thunderbolt 4 / USB4 |
| Mac16,5–Mac16,8; Mac17,6–Mac17,9 | Thunderbolt 5 / USB4 |

Specification examples: [M4 MacBook Pro](https://support.apple.com/en-us/121552), [M4 Pro/Max MacBook Pro](https://support.apple.com/en-us/121553). The allowlist spells out each identifier, not a family/prefix match. Adding a model requires verifying its identifiers, USB-C port uniformity and specifications.

Mixed-port layouts must not use a uniform profile. For example, [MacBook Neo](https://www.apple.com/macbook-neo/specs/) has USB 3 and USB 2 sockets. Mac mini models can have different front and rear capabilities. For these and other unlisted models, positive USB 2, USB 3 and DisplayPort protocol support can be read directly from validated IOPort services and SDK-defined USB host port properties when present. This does not establish a particular USB 3 rate or Thunderbolt generation. `CIO` support and raw registry version integers are not treated as Thunderbolt certification. Missing properties remain unknown. Manual per-port selection is available, including explicit Unknown; manual values are labeled as user settings in device details.

Physical side/order mapping remains user calibration. A capability profile never binds controller numbers or local registry paths to universal left/right locations. The app does not fetch specifications online; these are bundled source-backed facts and reference links only.

Automatic labels use a host Thunderbolt adapter’s supported speed mask and lane width, joined by its Socket ID to the physical connector number. Only adapters under a route-zero host switch are eligible; a dock’s own adapters cannot supply host capability. Duplicate dual-link adapters must agree. Unsupported or ambiguous schemas stay unknown. The label is Thunderbolt / USB4 with a maximum reported link rate; 40 Gb/s alone does not distinguish Thunderbolt 3 from Thunderbolt 4 certification. Reported USB/DisplayPort protocols are used when no maximum is available. An optional explicit user override takes precedence and lives under an advanced disclosure in port settings. Hardware discovery works independently of this profile list. Optional registry transport schemas are isolated in the hardware adapter and may vary across macOS versions and hardware.
