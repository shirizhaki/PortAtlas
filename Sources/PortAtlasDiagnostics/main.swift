import Foundation
import PortAtlasHardware

do {
    if CommandLine.arguments.contains("--power") {
        let connectors = (try? USBDiscovery.snapshot().connectors) ?? []
        let sampler = PowerSampler()
        defer { sampler.close() }
        for index in 0..<5 {
            let sample = sampler.sample(connectors: connectors)
            print("\(index): \(sample.chargingLabel) · \(sample.input?.label ?? "Unavailable") · \(sample.input?.source ?? "No input source")")
            for output in sample.outputs { print("Output: " + output.label + " · " + output.source) }
            if index < 4 { Thread.sleep(forTimeInterval: 1) }
        }
        exit(0)
    }
    if CommandLine.arguments.contains("--displays") {
        let capacities = DisplayDiscovery.linkCapacities()
        let edids = DisplayDiscovery.edids()
        for (id, report) in DisplayDiscovery.signals().sorted(by: { $0.key < $1.key }) {
            print("Display signal: \(report.signal.label) · DP payload capacity: \(capacities[id]?.payloadLabel ?? "Unavailable")")
            if let edid = edids[id] { print("EDID: \(edid.manufacturer) · \(edid.data.count) bytes verified · \(edid.detailedTimings.count) detailed timings") }
            print("macOS desktop modes: \(DisplayDiscovery.availableModes(for: id).count)")
        }
        exit(0)
    }
    let snapshot = try USBDiscovery.snapshot()
    print("Model: \(snapshot.modelIdentifier)")
    print("Controllers: \(snapshot.nodes.filter { $0.kind == .controller }.count)")
    print("Logical root ports: \(snapshot.nodes.filter { $0.kind == .port }.count)")
    print("Physical connectors: \(snapshot.connectors.count)")
    print("USB devices and hubs: \(snapshot.deviceCount)")
    print("Reported link rates: \(snapshot.nodes.compactMap { $0.speed?.label }.joined(separator: ", "))")
    print("Reported connector support: \(snapshot.connectors.compactMap(\.reportedSupportLabel).joined(separator: ", "))")
    print("Active video / Thunderbolt transport links: \(snapshot.connectors.flatMap(\.links).count)")
    print("External Thunderbolt routers: \(snapshot.nodes.filter { $0.transport != nil && $0.kind == .hub }.count)")
    print("Power source: \(snapshot.powerStatus.label)")
    if let watts = snapshot.powerStatus.adapterWatts { print("Reported adapter rating: \(watts) W (route unavailable)") }
    print("Unresolved parents: \(snapshot.nodes.filter { node in node.parentID != nil && !snapshot.nodes.contains { $0.id == node.parentID } }.count)")
    if CommandLine.arguments.contains("--connections") {
        for connector in snapshot.connectors {
            let devices = snapshot.nodes.filter { snapshot.connectorPath(for: $0.id) == connector.id && ($0.kind == .device || $0.kind == .hub) }
            print("\(connector.label): \(devices.map { "\($0.name) [\($0.speed?.label ?? "Unknown")]" }.joined(separator: ", "))")
        }
    }
} catch { fputs("Discovery failed: \(error.localizedDescription)\n", stderr); exit(1) }
