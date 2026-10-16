# Architecture

## Data flow

```text
IOKit notifications → coalesced event → background IORegistry snapshot
                                           ↓
                                  immutable topology model
                                           ↓
                        user socket assignments + presentation state
                                           ↓
                            SwiftUI graph and detail inspector
```

`PortAtlasCore` has no UI or hardware dependency. `PortAtlasHardware` depends only on Core and system frameworks. The app depends on both. Registry handles stay inside discovery passes. The optional SMC power sampler owns one locked read-only user-client connection per visible sampling session; no handle escapes the hardware module.

## Discovery and evidence

The adapter enumerates validated USB-C IOPort services as well as AppleUSBHostController, AppleUSBHostPort and IOUSBHostDevice services. This retains sockets even when no USB root or device is reported. IORegistry parent traversal supplies relationships, not names, Location IDs, or manufacturer guesses. Downstream hub ports are skipped in the presentation, and their device children connect to the nearest reported USB device ancestor. Root logical ports remain explicit. Class names and properties are compatibility assumptions isolated to the adapter; all calls use public IOKit functions.

The system's IOUSBHost enumeration speed key is read with the host enum, which differs from the older `Device Speed` enum. Absence and unrecognized values produce no speed. Only SDK-documented current allocation and hub supply keys are currently interpreted as mA. Full registry dictionaries are temporary and are never exported, logged, or saved.

Matching notifications for devices, ports, controllers, transport states and Thunderbolt switches are registered for first-match and termination. Iterators are exhausted to arm/rearm notifications. Events on the main queue debounce for 300 ms. Discovery runs off the main thread; one pass runs at a time, and an event arriving during a pass schedules one subsequent refresh. Errors leave the last successful snapshot visible and display an error state. Manual refresh remains available if notification setup fails.

A snapshot cannot be perfectly atomic across IORegistry reads. A device can disconnect while it is being read. Failed ancestry/property lookups produce missing information; orphan nodes remain visible, and ancestry traversal guards against cycles. These transient states require physical attach/detach validation.

## Identity and physical sockets

Registry entry IDs identify nodes only within a running system. They are not persisted as hardware identities. Root USB ports expose the SDK-defined `UsbIOPort` property. The adapter resolves that path with `IORegistryEntryFromPath`, checks IOPort conformance and a USB-C type description, and groups only roots with the same validated target. Controller numbers and Location IDs are never used to infer physical socket grouping or position.

Manual socket assignments use **model identifier + physical connector IOService path**, retaining a root path for compatibility. Selecting a recognizable device in settings maps its connector to a user-defined side and list order. This maps its USB 2/3 branches together and survives device replacement without keying on the device's identity. Conflicting old per-branch assignments remain unplaced until explicitly corrected. The device name may influence a decorative icon but never a connection, speed or physical location.

These associations need user verification after reboots and OS changes. A matching saved path does not prove an unchanged physical mapping. The user's local calibration is not a universal model profile. Future profiles must distinguish layouts (labels and coordinates) from independently verified hardware mapping evidence.

Configuration schema version 3 is JSON in Application Support. Versions 1–2 migrate while preserving socket IDs and assignments. Old near/far fields establish initial per-side order and are removed; old preset labels become numbered labels, custom names stay unchanged. List order supplies physical placement. Reordering only swaps entries on the same side and never changes an assignment. Duplicate socket IDs reject the settings file instead of crashing. Writes are atomic. Corrupt or future-version configurations disable saving until the user explicitly resets, preserving the original file. No captures, device serials or user calibration enter the repository.

## Graph presentation

The raw topology model preserves reported parent IDs for inspection. `PhysicalTopology` builds a separate projection: configured sockets with their direct USB devices, plus unplaced connections. Controllers and root protocol branches are omitted from this projection. Real hub/device relationships are preserved. Logical view shows the raw model. Both projections share MapViewport for bounded pan, anchor-based zoom, Fit and Focus. Viewport state is independent per view and stays stable across hardware and telemetry updates; automatic fitting occurs initially, on a viewport resize while in Fit mode, or when explicitly requested. Orphan devices remain visible; missing connector evidence never becomes an empty socket. `Empty` requires an observed inactive connector; otherwise the view reports that a USB device was not reported. An active observed transport link also establishes a connected state.

Companion root devices on one validated connector share the compact external-accessory presentation used by the physical view. Other reported hub/device rows remain inside that presentation. Downstream USB mass-storage devices and devices observed joining an established hub are displayed in separate cards, with an explicit edge to their reported hub parent; this is a display choice, not a claim that other children are physically built into an enclosure. Collapsing a hub also hides its separated storage cards. Logical ancestry is unchanged. Unknown enclosure boundaries remain unknown.

The UI uses native SwiftUI controls and Canvas curves. Physical view and Logical view support bounded dragging, pinch zoom, zoom buttons, and fitting the whole map to the viewport. Zoom changes layout dimensions and native font sizes; it does not scale a cached layer. Canvas paths redraw at the current size. Built-in battery service presence selects a generic laptop silhouette; otherwise a generic desktop enclosure is drawn. This appearance choice does not establish port capabilities. Selection and branch collapse are presentation state. Synthetic fixtures exist only in the test target and do not contain real hardware identifiers.

## Future adapters and distribution

`TransportDiscovery` separately reads optional active IOPortTransportState observations (DisplayPort and CIO) and external IOThunderboltSwitch routers. Host routers with route zero are excluded. Router ancestry is preserved where both endpoints are observed. These class/property schemas are compatibility assumptions, not stable SDK guarantees. No controller index, raw version integer or shared name supplies a socket route, certified generation or enclosure identity. Complete Thunderbolt/USB4 graphs require further hardware validation and trustworthy typed links. HDMI and SDXC should be separate physical-connection adapters rather than forced into USB ancestry.

The app currently runs without sandboxing or administrator privileges. Sandboxed registry availability needs separate testing before an App Store decision. Do not add device claims, driver installation, helper daemons, root privileges, private frameworks, or private API calls to solve missing observability. Investigate limitations and document them first.

## Apple references

- [IOServiceAddMatchingNotification](https://developer.apple.com/documentation/iokit/1514362-ioserviceaddmatchingnotification)
- [IONotificationPortCreate](https://developer.apple.com/documentation/iokit/1514480-ionotificationportcreate)
- [IOUSBHost enumeration speed property](https://developer.apple.com/documentation/iousbhost/iousbhostmatchingpropertykey/speed)

The installed SDK's `IOUSBHostFamilyDefinitions.h` and `IOUSBHostDefinitions.h` provide the property and speed enum definitions used by the adapter.

## Mounted storage

Disk Arbitration maps mounted filesystem URLs to IOMedia. Storage bars are attached only when IOService ancestry reaches an enumerated IOUSBHostDevice. Foundation supplies total and available filesystem bytes; used space is their difference. No volume names or capacity records are persisted. Unsupported ancestry (including some synthesized APFS volumes), unavailable metadata and invalid capacity values omit the bar. Per-volume bars are never added into an aggregate, because APFS volumes can share container capacity. USB and workspace mount/unmount/rename notifications refresh the snapshot; manual refresh updates space after file changes.

## Port capabilities

Automatic capability labels are model-independent. A host IOThunderboltPort's supported speed mask and width supply a maximum symmetric link rate, joined by its Socket ID to the connector number. Route-zero switch ancestry excludes external docks. Repeated dual-link adapters must agree; unknown masks and widths are omitted. This proves a maximum reported Thunderbolt/USB4 rate, not a certification generation or USB 3 rate. Other ports use positively reported USB/DisplayPort protocols. Explicit manual overrides remain optional under advanced port settings. MacCapabilityProfile is retained only for optional specification-reference links, not automatic labels. See [capability evidence](PortCapabilities.md).

## Display and Mac power observations

AppKit NSScreen and Quartz display services enumerate external displays and their names/pixel dimensions without capturing screen content. Screen parameter notifications refresh this list. Display identities are not joined to USB devices or DisplayPort observations without endpoint evidence; the map shows unassigned displays separately.

`PowerDiscovery` uses public IOKit Power Sources APIs for AC/battery source, internal-battery charging state and optional external-adapter wattage. Power source notifications trigger a coalesced refresh. Wattage is the reported adapter rating, not instantaneous consumption or measured Power Delivery negotiation. Active CC transport alone does not identify a Mac charging port. The input route is inferred only from one reported active selected PD contract while the Mac reports external power, or from the sole connected MagSafe with every detected USB-C explicitly inactive. Competing contracts and unknown states remain unassigned. A contract is not an explicit report of the selected input and this inference is labeled in details.

Connector observations can be calibrated without a logical USB root. Saved calibration stays in Application Support, and accidental settings/capture copies are covered by repository ignore rules. None of the display, power or transport observations are persisted.

## Helper feasibility

A separate helper can isolate discovery or collect explicit diagnostic observations. A privileged helper should only be introduced after demonstrating a concrete required source that ordinary discovery cannot read. Higher privilege does not itself establish an undocumented mapping between a power source and a physical port. No privileged service is installed in this initial version. If justified later, use Apple Service Management with a narrow read-only interface and preserve the same unknown-route semantics.

## Physical enclosure boundaries

Reported USB ancestry proves a transport parent relationship, not a physical enclosure boundary. USB hub descriptors provide DeviceRemovable information, and host port status can report captive/internal types. These may support a built-in classification when available and validated, but are not currently read or used to collapse devices into a dock enclosure. On the locally observed hub the Ethernet and SSD records both exposed the same generic USBPortType value; that observation does not distinguish built-in Ethernet from the external SSD. Never classify by device name alone.

Separate cards extend outward from each socket: left/right for side sockets, above for Back and below for Front. Multiple downstream tiers retain their reported parent links. AttachmentHistory keeps session-only observations and treats a new child of a hub seen for at least two seconds as a later attachment. This heuristic avoids some staggered initial enumeration but cannot prove enclosure boundaries. It resets when the device disappears and is never persisted.

## Thunderbolt and PCIe routing

External IOThunderboltSwitch routers are part of the connection graph. The host
router (route zero) is excluded. An active CIO transport's UID is joined only
when both the external router and physical USB-C port match uniquely; the UID
is transient and is never persisted. PCI branches are joined through their
nearest explicit Thunderbolt Entry ID reference to a Thunderbolt port/router.
This attaches a dock's USB controller and external NVMe controllers without
guessing from controller indexes. Physical view skips controller/logical-port
nodes while Logical view retains them. Missing evidence stays unassigned.

Selected USB-PD contracts are read from IOPortFeaturePowerSource in the feature subtree below
a validated connector. Only WinningPowerSourceOption is used, never the largest
advertised option. This is a contract limit, not measured consumption or proof
of every intermediate power hop. Display endpoints still require separate route
evidence. AppleATCDPAltModePort DisplayHints can be absent behind a TB dock.

Research reference: [WhatPort](https://github.com/darrylmorley/whatport), especially
ChargerReader.swift, DisplayReader.swift and ThunderboltReader.swift (MIT).
Its property schemas helped identify the selected per-port USB-PD contract;
no external runtime dependency or privileged helper was added. The USB/PCIe
route joins were validated against local registry references. Raw local captures
remain outside the repository; tests use synthetic device identities.

Link rates for external Thunderbolt routers come from their own upstream
IOThunderboltPort: current speed code per lane multiplied by current width.
Only recognized symmetric widths are decoded; supported-speed masks and
Link Bandwidth are not used as current rates. PHY lane labels use the explicit
parent device-tree port-number and unique active report, never controller order.
CIO provisioned tunnel protocols describe shared transport allocation, not which
individual endpoint occupies a dedicated lane. USB 3 active transport descriptions
are surfaced when reported. These optional schemas were researched with WhatPort
and the current 40 Gb/s dock/enclosure links checked against System Information.

Display transport scanning includes descendants of CIO, not just direct IOPort
children. A checksum-valid EDID vendor/product/serial tuple must match exactly
one online external CoreGraphics display, with one reported sink and one route.
Raw EDID and serials are not retained. The display card indicates passage via the
host-facing router, not a claim about a particular dock output or unreported
downstream adapters. Unmatched and ambiguous screens remain unassigned. Connected
socket headings show current root transport and link rate; capabilities remain
in Settings/details and on empty sockets.

## Physical view simplification

PhysicalPresentation combines only a transport router with exactly one direct,
leaf PCIe/NVMe storage child and no other children. Names and vendors play no role;
multiple drives, USB controllers, missing transport evidence, and indirect links
prevent combination. Logical view retains every discovered node. Combined cards
show the enclosure link rate and the drive's volume usage, with separate detail
access for the drive. This is a presentation grouping, not enclosure certification.

Other components are expandable groups, never labeled built-in. Storage, displays,
transport routers and later-observed attachments remain separate cards. Users can
keep other components visible for the current connection through their context
menu. These session choices are not persisted. When a parent is folded, the line
starts at the nearest visible ancestor; the card still names its reported parent.
Labels distinguish system-reported connections, EDID-matched display routes,
session timing hints, and manually assigned physical positions.


## Inspector, telemetry and interaction

Selection is an app presentation value (Mac, socket, unplaced connector, device,
display or connection), independent of raw registry identity. One nonmodal right
inspector shows only relevant sections. Device selection survives switching maps;
disconnects remove invalid selections. Selection highlights the reported route.
Empty sockets remain compact, with capabilities and evidence in the inspector.
Map cards retain names, current link rate and a short function-specific summary.
At lower zoom, secondary text and volume/components detail fold away before text
becomes excessively small. Cmd+0 fits the map, Cmd+2 focuses selection, keyboard arrows pan, and native buttons accept keyboard
focus, and Escape closes the inspector. The map uses a distinct background with
separators from the header and status bar.

PowerTelemetry prefers read-only AppleSMC DC-input rails: PDTR watts, VD0R volts and ID0R amps. PDTR is preferred; valid V × I is a fallback when both rails are present. Missing/zero negotiation rails cannot fabricate a zero input. Optional AppleSmartBattery.PowerTelemetryData is the fallback, and the UI explains that it can update slowly. These are whole-Mac input measurements, never attributed to a connector from contract inference. Battery power remains separately derived from signed battery V × I. Current battery-controller ExternalConnected/IsCharging flags override cached IOPS flags when valid; IOPS remains the fallback.

The app registers actual map windows rather than guessing visibility from window width. Power starts with an immediate sample and continues about once a second while a map window is visible; it stops on hide/minimize/sleep and resumes with an immediate sample and fresh history. Network reads use an independent three-second task and cannot stall power updates. A session owns one locked read-only SMC connection, closed when sampling stops. Unsupported key types, ABI layout, failed opens and reads degrade to optional fallback; there is no privilege request, write operation, or device control.
An in-memory 60-second graph breaks over missing readings and sampling gaps.
It never writes measurements to settings or files. This sampler does not rescan
topology. Optional Ethernet telemetry is refreshed independently every three seconds and joins
IONetworkController SDK link status/speed to a device only through actual registry
ancestry. Network speed is separate from USB speed. Unsupported network drivers
produce no reading. External-display desktop scaling and render dimensions come from CoreGraphics.
Active signal timing comes from a uniquely identity-matched Apple Silicon framebuffer report; unavailable timing stays unreported. It is not the DP link rate.

Cable metadata is an optional unique SOP' identity beneath a validated active
connector. The WhatPort CCReader decoding is MIT-attributed. Product type and PD
revision are reported without inventing cable speed/current ratings. Selected PD
limits and advertised maximum remain separate. Per-device power metering, measured per-device
traffic, duplex inference and undocumented error-counter schemas are not enabled.
Connected-line animation is illustrative, can be toggled for the session, stops
in Logical view and honors Reduce Motion.

## Map hit targets and connection appearance

Card surfaces select their port or device across the background and padding. Nested device buttons, component toggles and collapse controls retain their own actions. Both map viewports dismiss the inspector on a tap outside the resolved card, Mac, wire and map-control hit regions; dragging and pinching do not dismiss selection. Wire hit regions are transformed through their anchors with the map, so zoom and pan preserve selection behavior.

Connection appearances retain simultaneous functions: green for input power, amber for output power, teal for data and red for displays. Shared borders space all reported functions six points apart at normal zoom instead of prioritizing one color. Physical wires use separated parallel tracks that converge at the socket and card endpoints and preserve inward power versus outward illustrative data/display motion. Mac wire endpoints and drawing share chassis coordinates; small socket marks are drawn above the illustration at the chassis edge.


## Display timing and bandwidth

`DisplayDiscovery` is a read-only compatibility adapter for optional Apple Silicon framebuffer schemas. It accepts an active external framebuffer and exactly one nonvirtual, progressive, nonsplit `TimingElements` entry selected by `DPTimingModeId`. Horizontal/vertical active dimensions and 16.16 timing frequencies describe the output signal. A unique CoreGraphics vendor/product/serial match is required; duplicate identities and competing reports remain unavailable. Native format and CoreGraphics desktop/render size stay separate. Screen changes and connection refreshes replace readings; there is no model-specific resolution table or persistent display telemetry.

Active EDID-matched DisplayPort transport state supplies lane count and known RBR/HBR/HBR2/HBR3 rates. Raw rate and 8b/10b payload capacity are separate facts. Unknown link schemas, UHBR and multi-sink or ambiguous identities remain unavailable. Capacity does not imply allocated Thunderbolt bandwidth or measured video traffic; no remaining-bandwidth subtraction or color/DSC assumptions are made.


## Outgoing power

The visible-window power sampler also reads host-port power output. Optional SMC DxJV/DxJI rails join through exactly matching DxUI and HPM ancestor UUIDs; indices are never interpreted as connector positions. Hardware UUIDs stay within live snapshots and never enter saved calibration. On unsupported machines, valid AppleSmartBattery.PowerOutDetails reports join only unique host USB-C PortNumber/PortIndex values. Milliwatts are checked against reported voltage × current. Duplicate reports, ambiguous identities, inactive ports, incoming contracts and stale samples produce no output attribution. A valid live zero suppresses a stale positive firmware report.

The Physical map gives a verified output port an amber border and thicker track animated from Mac to card. Incoming power keeps a green thicker track and its inward direction. Direction badges and the legend use down/up arrows, and display/data tracks remain thinner. The inspector describes power supplied at the Mac connector and configured output limits, without claiming the attached battery is charging or that ordinary 5 V output negotiated USB-PD. Power delivery beyond a dock is not attributed. Sampling shares the existing one-second session and closes the read-only SMC connection on hide/minimize/sleep.


## User-controlled physical component placement

Each downstream accessory can use Automatic, Dock component, or Separate accessory placement. Explicit grouping overrides attachment-history hints; explicit separation overrides automatic folding, including combined NVMe endpoints. The projection changes which cards are visible, while source parent IDs, Logical layout, transport routing, rates, and power evidence stay intact. Wires still follow the nearest visible source ancestor. Inspector and context-menu controls use the same preference.

Choices are atomically saved to Application Support/PortAtlas/presentation.json. Keys hash the Mac model, registry connection path and device identity; registry entry IDs, raw device names and raw paths are not persisted. A choice survives reenumeration on the same route. Moving to a different USB connection intentionally uses Automatic until the user chooses again. Ambiguous paths cannot receive a preference. Corrupt preferences stay intact until the user resets them. The source ignore rules exclude accidental copies.

The Mac illustration draws flat vector USB-C plug silhouettes for active connections, with a distinct MagSafe shape. Cable endpoints meet the short connector stem rather than running directly into the chassis. Device and host-port cards share role icons; only direct host-facing roots inherit that port's power evidence. Downstream device power is never inferred from the host's draw. Total output under the Mac sums available fresh, uniquely scoped host-port readings; unsupported/missing output is unavailable rather than zero.

Function icons appear once at the top-right of each Physical card. Embedded component rows do not duplicate them, and lower power readouts keep text only. Keyboard keys have no markings. Plug silhouettes use flat fills and outlines rather than metallic details.

Socket tips and plug heads use neutral fills and outlines; function colors remain on cable tracks and cards.

## Map materials

The Appearance preference offers Follow System (default), Light and Dark. It is stored locally in app UserDefaults, independently of port calibration, and never enters the source package. The application appearance override covers SwiftUI content, AppKit visual-effect materials, native controls and all app windows. Follow System clears the override so macOS appearance changes continue to propagate. A saved choice applies before windows appear and changes immediately from Settings.

The canvas uses AppKit's semantic under-window material, and the inspector uses its sidebar material. Both blend behind the window and follow window activity. Shared device and socket cards use regular SwiftUI material with a neutral wash and a restrained edge highlight; role colors remain on borders, icons and tracks. Native Liquid Glass is reserved for floating map controls. Reduce Transparency or increased contrast replaces all custom translucent surfaces with opaque system colors. Background materials do not receive hits or accessibility focus, and the existing card selection, nested controls, pan/zoom and blank-map dismissal remain independent of the surface treatment.

Light appearance uses deeper role colors, a reduced white highlight, and stronger neutral card edges. Selection changes unrelated card borders and wire emphasis without fading card text, symbols or storage information. The canvas has a subtle neutral shade distinct from the inspector. The shared palette also covers role labels and measurements in the inspector.

## Full-screen controls

Map windows retain the native full-screen implementation. On macOS 15 and later, the toolbar stays visible in full screen. Its enter/exit button registers Control–Command–F and delegates to the key map window's `toggleFullScreen`; native View-menu and window controls remain available. Actual window notifications update the button label, including when full screen is toggled through system controls. Escape continues to dismiss the inspector.

### Built-in HDMI

Apple Silicon HDMI ports are discovered from IOPort PortTypeDescription, including while empty. No model catalog is required for presence. A single unassigned HDMI port appears automatically on the right of a laptop or the back of a desktop; this is a default position, not hardware position evidence. Settings can turn it into an ordinary saved assignment for side and order changes. Multiple unassigned HDMI connectors remain unmapped rather than being merged. Settings stay in Application Support.

Display identity matching reuses the existing unique EDID-to-CoreGraphics join. The IOPortTransportStateDisplayPort child of a physical HDMI connector is presented as HDMI; internal DisplayPort rates and lanes are omitted from HDMI link capacity. Ambiguous displays remain unassigned. HDMI has no USB power contracts, cable PD identity, controller-power join, or inferred data role. Existing signal timing stays separate from desktop scaling; unavailable timing stays unavailable. Screen changes trigger an immediate scan and one cancellable settling scan after 1.2 seconds, alongside existing wake and transport notifications. Logical display nodes retain the discovered route without adding invented USB parents.

Validation before release should include a directly connected HDMI display, unplug/replug, scaled resolution and refresh changes, sleep/wake, and simultaneous HDMI plus USB-C/dock displays. Live HDMI routing and selected signal timing were subsequently verified on a connected LG TV; the broader unplug/replug and sleep/wake matrix remains to be tested.

### Display capabilities and variable refresh

The active selected controller timing may expose MinimumVariableRefreshRate and MaximumVariableRefreshRate in 16.16 fixed point. Only a validated range on that selected timing is presented as VRR; a display-wide support flag alone does not establish selection. The nominal timing rate is kept separate from the variable range and no instantaneous HDMI refresh or application FPS is fabricated. Missing or invalid range fields stay unreported.

Available modes use CGDisplayCopyAllDisplayModes, filter for desktop usability, validate dimensions/rates, deduplicate, and sort deterministically. They describe configurable macOS desktop modes, including any render scaling, rather than an exhaustive set of physical signal timings. Zero refresh rates remain unspecified.

Live EDID is uniquely matched by the existing vendor/product/serial join on active single-sink display transports. The base block and every declared extension must fit bounded input and pass their checksum. Identity, version, manufacture year, and progressive detailed timings from the base and CTA detailed timing areas are decoded. Other video data blocks, standard timings, and DisplayID timings are not decoded; the UI explicitly labels the detailed-timing list as incomplete. Raw validated EDID is copyable on demand. EDID and mode readings stay in memory and are not persisted as model databases or source fixtures. Duplicate display identities and competing routes remain unavailable.

Verified live on an HDMI-connected LG TV: 3840 × 2160, selected VRR 40–120 Hz, nominal 120 Hz, validated 256-byte EDID, and 114 macOS desktop modes. Core tests use synthetic EDID, including corrupt/truncated blocks, extension bounds, selected versus display-wide VRR ranges, and scaled desktop modes.

### Portable first-run matching

The matching guide compares session-only sets of accessory roots per validated host USB-C/USB-A connector. Exactly one new host-root arrival suggests a connection for human confirmation. Ambiguous simultaneous changes stay unselected. Adding a child to an existing dock does not suggest a new Mac socket. The user chooses side/name and may reuse an existing empty position. Occupied positions cannot be overwritten by this guide. Assignment is prepared in a value copy, saved atomically, then adopted by the store. Existing settings schema 3 is unchanged. Component preferences are independent and untouched.

USB-A support requires an explicit USB-A IOPort with BuiltIn=true. Internal USB ports and dock USB-A connectors do not create Mac sockets. Companion branches group only through a validated shared connector path. No USB-PD or host Type-C PHY identity is queried for USB-A, and it cannot become an incoming-power candidate. Legacy desktops without these IOPorts remain unmapped until supported by verified connector evidence. Synthetic tests establish behavior; physical USB-A host validation remains outstanding.
