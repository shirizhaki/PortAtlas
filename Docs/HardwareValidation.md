# Hardware validation

Automated tests cover topology safety, speed interpretation, connector grouping, actual hub preservation, unplaced connections, conflicting old assignments, configuration migration, round trips and corruption. They cannot establish physical socket positions or OS registry stability.

Before claiming hardware support, record macOS version and Mac model only; keep captures with identifying information outside the repository.

- [ ] Start with no external USB devices. Inspect reported controllers/root ports; verify the UI does not imply every logical port is an external socket.
- [ ] Connect a USB 2 mouse/keyboard to each socket and confirm the device appears beneath a reported port.
- [ ] Repeat with a USB 3 SSD and compare root paths. Verify branches with the same validated UsbIOPort target follow one connector assignment.
- [ ] Attach a USB hub; confirm parent-child links against System Information, including a hub behind another hub.
- [ ] Rapidly unplug/replug a hub while a child detail card is selected. Confirm no crash and eventual convergence.
- [ ] Unplug during manual refresh. Confirm stale selection is cleared and errors are visible if a scan fails.
- [ ] Sleep/wake with devices attached. Confirm live notifications or manual refresh recover the current topology.
- [ ] Reboot and verify every saved physical assignment, including USB 2 and USB 3 paths.
- [ ] Attach a Thunderbolt dock. Compare USB children, external routers and active transport observations against System Information. Confirm host routers are excluded and unknown socket/enclosure routes remain unassigned.
- [ ] Connect a display directly and through a dock. Check external display names/dimensions and active DisplayPort observations; display identity must stay unassigned unless its route is established.
- [ ] On an Apple Silicon laptop with MagSafe, verify the automatic leftmost socket appears without changing settings. On a laptop without MagSafe and on a desktop, verify no MagSafe socket is fabricated.
- [ ] Attach MagSafe and a charging USB-C dock together. Verify selected input contracts take precedence, ambiguous sources stay unknown, and a merely connected cable never claims incoming power. Repeat at full battery and with optimized charging paused.
- [ ] Verify red display and green input-power outlines coexist on a single dock connection. Animated marks must stop under Reduce Motion and when no connection is active.
- [ ] Connect/disconnect power directly, through a dock and through MagSafe where available. Compare charging state and adapter rating with macOS. Confirm no guessed charging socket and no claim of measured consumption.
- [ ] Assign a discovered connector with no USB roots; verify it remains visible and its assignment survives relaunch.
- [ ] Compare reported enumeration rates with System Information, separately from benchmark throughput.
- [ ] Verify power contracts and allocations never appear as measured consumption; optional live readings must identify their measurement scope and source.
- [ ] Exercise light/dark modes, window resizing, zoom/pan/Fit, branch collapse, Settings via the macOS menu, side-order changes and removal of assigned sockets.
- [ ] Close the last window using the red button and ⌘W; confirm the app quits and a fresh launch opens a window. Close Settings while the main window remains open; confirm the app stays running.
- [ ] Double-click the native title bar from a smaller window; verify the system-configured resize action and restoration, including on a second display.
- [ ] On a desktop Mac, confirm the generic desktop illustration and Front/Back panel order.
- [ ] Compare capability profiles with Apple specifications. Unknown or mixed-port models must not inherit a guessed uniform capability; reported protocol fallback must not imply an exact USB speed or Thunderbolt generation; manual overrides must survive relaunch.
- [ ] Confirm crisp text and icons at high zoom and inspect mounted storage bars against Finder.
- [ ] Check Activity Monitor when idle; the app should not schedule repeated discovery passes.
- [ ] Test sandboxed discovery separately before choosing an App Store distribution strategy.

Initial local validation only establishes the build and currently observed registry state. It does not certify the matrix above.


## Inspector and telemetry

- Verify clicking the Mac, an empty socket, MagSafe, a device and a wire opens
  relevant details without blocking the map. Escape closes the inspector.
- Verify selection, collapse state and independent pan/zoom survive switching views.
- Verify Fit and Focus, anchor-based pinch zoom, keyboard focus and arrow-key pan.
- Verify small zoom levels retain readable names and link rates; light/dark map
  backgrounds remain visibly distinct from the header.
- Plug/unplug while zoomed: card updates must not reset the viewport.
- Compare Mac input telemetry to a trusted meter where available. A PD contract
  may be much higher than current draw and must never replace a live measurement.
- Test AC/battery transitions, zero readings, absent telemetry, sleep/wake and
  hide/minimize. Old power readings and graphs must not survive an input change.
- Check battery charging/discharging sign independently of Mac input.
- Check fixed and variable refresh displays; zero refresh is unavailable.
- Check Ethernet link up/down and speed negotiation independently of USB rate.
- Check active/passive cable identity on supported hardware; a missing SOP' or
  ambiguous report must produce no cable facts.


## Scaled displays and shared connections

- Connect a 4K display with a 2560 × 1440 scaled desktop. The display card must use active signal timing (3840 × 2160 at the selected refresh); the inspector keeps Looks like and Rendered desktop separate.
- Change the actual output mode to a lower resolution. Native capability must not overwrite the lower active signal. Check mode changes, reconnect and sleep/wake.
- With identical displays, virtual screens or absent framebuffer schemas, ambiguous signal information must stay unavailable. Test direct DP Alt Mode, Thunderbolt docks and DP-to-HDMI adapters on additional Apple Silicon Macs.
- HBR3 × four lanes should show 32.4 Gb/s raw and 25.92 Gb/s payload capacity. Neither value is claimed as video traffic or reserved Thunderbolt bandwidth. Unknown encoding must not use the HBR calculation.
- Inspect simultaneous red/green/teal port borders and parallel cable tracks at low/high zoom, with animation off and Reduce Motion. Check card, wire, collapse and blank-map interactions.


## Power supplied by the Mac

- Connect a phone directly to each USB-C port: verify the amber outward track and output label follow the port, alongside the data track. Compare output to an external USB meter where available.
- Confirm a powered dock can supply the Mac on one port while another port supplies a phone. Incoming and outgoing directions must stay independent.
- Disconnect or move the phone: old output must clear. Test fully charged phones, zero draw, sleep/wake and minimize/resume.
- Check desktop Macs and older Apple Silicon machines with missing SMC output identities. Optional readings must degrade without assigning D-channel indices to physical positions.
- A phone connected through a powered dock must not be credited with the Mac's host-port draw. Output describes the Mac connector, not a downstream charging path or phone battery state.

- Verify power-in and power-out colors, arrows and thicker tracks remain distinct with motion disabled, at low/high zoom, and while display/data share a cable.


## Component placement and cable ends

- In the receiver inspector, choose Separate accessory. Refresh, restart and reconnect at the same USB route: the receiver should retain its own card. Choose Dock component to fold it back; Automatic restores recognition hints.
- Inspect Logical before/after the choice: actual parent and device count must remain unchanged. Test nested hubs and manual separation of combined NVMe endpoints.
- Use the same options through a component's context menu. Check folded components remain inspectable and downstream wire selection/Focus still work.
- Check plug heads are seated at the chassis edge at low/high zoom, including left/right/front/back USB-C and MagSafe. Only active cables get plugs.
- Direct SSD and dock card icons should retain simultaneous data, display, and power roles. Downstream storage gets data without invented power evidence.
- Compare the Mac's total output with the sum of reported port output. Stale, missing and ambiguous outputs must not become zero or double-counted totals.

- Verify function icons appear once, at the top-right of mapped, downstream and unmapped Physical cards. Embedded component rows and power badges must not add a second icon row. Check the unmarked keyboard and flat connector heads at high zoom.

## First-run portability

- On a separate user account or backed-up empty ports.json, open Match ports. Confirm discovery starts without model-specific positions. Keep presentation.json untouched when testing only port layout.
- Move one USB device across every socket. A single new host connection may be suggested, but no side is chosen automatically. Confirm simultaneous arrivals require manual choice and connecting a child behind an existing dock does not select another Mac socket.
- Save, relaunch, reconnect, reorder, and reuse a pre-created empty slot. Attempt to replace an occupied position; the guide must refuse. Disconnect before saving; stale selection must not persist.
- Test built-in USB-A on Apple Silicon mini/Studio desktops with USB 2 and USB 3 devices. Only explicit BuiltIn USB-A IOPorts may become host connectors. Dock USB-A, internal USB branches, and missing BuiltIn metadata must not fabricate Mac sockets. Validate power exclusion and Logical ancestry.
- Run the matrix on an early Apple Silicon laptop, a laptop without MagSafe, and a desktop with mixed front/rear capabilities, across macOS 14 and current macOS. Record model/OS/protocol coverage without serials or raw dumps.
