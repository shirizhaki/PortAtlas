import Testing
import Foundation
@testable import PortAtlasCore

struct PortConfigurationTests {
    private let logical = HardwareNode(id: "session-1", name: "Port", kind: .port, registryPath: "IOService:/controller/port")
    @Test func testAssignmentSurvivesNewSessionIDButIsScopedToModel() {
        var config = PortConfiguration()
        let socket = PhysicalPort(name: "Left USB-C", side: .left)
        config.ports = [socket]; config.assign(logical, model: "Mac-A", to: socket.id)
        let reconnected = HardwareNode(id: "session-2", name: "Port", kind: .port, registryPath: logical.registryPath)
        #expect(config.physicalPort(for: reconnected, model: "Mac-A") == socket)
        #expect(config.physicalPort(for: reconnected, model: "Mac-B") == nil)
    }
    @Test func testCompanionBranchesMaySharePhysicalSocket() {
        var config = PortConfiguration()
        let socket = PhysicalPort(name: "Right", side: .right)
        config.ports = [socket]
        let companion = HardwareNode(id: "usb3", name: "USB 3 port", kind: .port, registryPath: "IOService:/other/port")
        config.assign(logical, model: "Mac-A", to: socket.id)
        config.assign(companion, model: "Mac-A", to: socket.id)
        #expect(config.assignments.count == 2)
        config.removePort(socket.id)
        #expect(config.assignments.isEmpty)
    }
    @Test func testNeverAssignControllerOrUnavailablePath() {
        var config = PortConfiguration()
        let socket = PhysicalPort(name: "Left", side: .left); config.ports = [socket]
        config.assign(HardwareNode(id: "c", name: "Controller", kind: .controller, registryPath: "controller"), model: "Mac", to: socket.id)
        config.assign(HardwareNode(id: "p", name: "Port", kind: .port), model: "Mac", to: socket.id)
        #expect(config.assignments.isEmpty)
    }
    @Test func testSettingsRoundTripAndCorruptionDoesNotOverwriteFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("ports.json"))
        var config = PortConfiguration(); config.ports = [PhysicalPort(name: "Left", side: .left)]
        config.assign(logical, model: "Mac-A", to: config.ports[0].id)
        try store.save(config); #expect(try store.load() == config)
        let corrupt = Data("not-json".utf8); try corrupt.write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try Data(contentsOf: store.url) == corrupt)
    }
    @Test func movingWithinSidePreservesAssignmentsAndOtherSides() {
        let a = PhysicalPort(name: "A", side: .left)
        let b = PhysicalPort(name: "B", side: .right)
        let c = PhysicalPort(name: "C", side: .left)
        var config = PortConfiguration(); config.ports = [a, b, c]
        config.assign(logical, model: "FixtureMac", to: a.id)
        let assignments = config.assignments
        config.movePort(c.id, by: -1)
        #expect(config.ports(on: .left).map(\.id) == [c.id, a.id])
        #expect(config.ports[1] == b)
        #expect(config.assignments == assignments)
        config.movePort(c.id, by: -1)
        #expect(config.ports(on: .left).map(\.id) == [c.id, a.id])
    }
    @Test func oldPositionsMigrateToStableListOrder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ConfigurationStore(url: dir.appendingPathComponent("ports.json"))
        let json = """
        {"schemaVersion":2,"ports":[
        {"id":"00000000-0000-0000-0000-000000000001","name":"Left · near","side":"left","position":"near"},
        {"id":"00000000-0000-0000-0000-000000000002","name":"My custom right","side":"right"},
        {"id":"00000000-0000-0000-0000-000000000003","name":"Left · far","side":"left","position":"far"}
        ],"assignments":[{"modelIdentifier":"FixtureMac","registryPath":"fixture://port","physicalPortID":"00000000-0000-0000-0000-000000000001","assignedAt":0}]}
        """
        try Data(json.utf8).write(to: store.url)
        let result = try store.load()
        #expect(result.schemaVersion == 3)
        #expect(result.ports(on: .left).map(\.name) == ["Left 1", "Left 2"])
        #expect(result.ports(on: .right).first?.name == "My custom right")
        #expect(result.assignments.first?.physicalPortID == result.ports(on: .left).last?.id)
        try store.save(result)
        #expect(try store.load() == result)
        #expect(!(try String(contentsOf: store.url)).contains("position"))
    }
    @Test func duplicatePortIDsRejectSettingsWithoutModifyingTheFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigurationStore(url: dir.appendingPathComponent("ports.json"))
        var config = PortConfiguration()
        let port = PhysicalPort(name: "Duplicate", side: .left)
        config.ports = [port, port]
        try store.save(config)
        let original = try Data(contentsOf: store.url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try Data(contentsOf: store.url) == original)
    }
    @Test func testUnsupportedSettingsVersionIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("ports.json"))
        var config = PortConfiguration(); config.schemaVersion = 4
        try store.save(config); #expect(throws: (any Error).self) { try store.load() }
    }
}
