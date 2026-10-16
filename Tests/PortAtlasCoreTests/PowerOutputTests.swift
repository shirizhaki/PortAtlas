import Foundation
import Testing
import PortAtlasCore
@testable import PortAtlasHardware

struct PowerOutputTests {
    let date = Date(timeIntervalSince1970: 1000)
    let uuid = "11112222333344445555666677778888"
    var report: [String: Any] { ["PortIndex": 2, "Watts": 10000, "AdapterVoltage": 5000, "Current": 2000, "ConfiguredVoltage": 5000, "ConfiguredCurrent": 3000] }
    func port(id: String = "port", number: Int = 2, uuid: String? = nil, active: Bool = true, contract: Int? = nil) -> HardwareConnector {
        HardwareConnector(id: id, number: number, connectionActive: active, powerContractWatts: contract, controllerUUID: uuid)
    }
    @Test func totalOutputKeepsPortScopeFreshnessAndUnknowns() throws {
        let a = try #require(PortPowerOutput(connectorID: "a", watts: 10, volts: 5, amps: 2, source: "Fixture", sampledAt: date))
        let b = try #require(PortPowerOutput(connectorID: "b", watts: 5, volts: 5, amps: 1, source: "Fixture", sampledAt: date))
        #expect(PortPowerOutput.measuredTotal([a, b], at: date) == 15)
        #expect(PortPowerOutput.measuredTotal([], at: date) == nil)
        #expect(PortPowerOutput.measuredTotal([a], at: date.addingTimeInterval(6)) == nil)
        #expect(PortPowerOutput.measuredTotal([a, a, b], at: date) == 5)
    }
    @Test func reportedOutputUsesMilliwattsAndDoesNotBecomeMacInput() throws {
        let sample = PowerTelemetry.parse(["PowerOutDetails": [report]], status: MacPowerStatus(externalPower: false), at: date, connectors: [port()])
        let output = try #require(sample.outputs.first)
        #expect(output.watts == 10 && output.volts == 5 && output.amps == 2)
        #expect(output.configuredWatts == 15)
        #expect(sample.input == nil)
        #expect(output.isFresh(at: date.addingTimeInterval(6)) == false)
    }
    @Test func hardwareIdentityWinsOverChannelAndPortNumbers() throws {
        let channel = SMCInputReader.PortReading(uuid: uuid, volts: 5, amps: 1)
        let output = try #require(PowerOutputDiscovery.resolve([report], smc: [channel], connectors: [port(number: 4, uuid: uuid)], at: date).first)
        #expect(output.connectorID == "port" && output.watts == 5)
        #expect(output.configuredWatts == nil)
        #expect(PowerOutputDiscovery.resolve([], smc: [channel], connectors: [port(uuid: "99999999999999999999999999999999")], at: date).isEmpty)
    }
    @Test func liveZeroSuppressesStaleOutputAndDisconnectClearsIt() {
        let channel = SMCInputReader.PortReading(uuid: uuid, volts: 5, amps: 0)
        #expect(PowerOutputDiscovery.resolve([report], smc: [channel], connectors: [port(uuid: uuid)], at: date).isEmpty)
        #expect(PowerOutputDiscovery.resolve([report], smc: [], connectors: [port(active: false)], at: date).isEmpty)
        #expect(PowerOutputDiscovery.resolve([report], smc: [], connectors: [port(contract: 60)], at: date).isEmpty)
    }
    @Test func duplicateIdentitiesNumbersAndReportsStayUnassigned() {
        let channel = SMCInputReader.PortReading(uuid: uuid, volts: 5, amps: 1)
        #expect(PowerOutputDiscovery.resolve([], smc: [channel], connectors: [port(uuid: uuid), port(id: "second", number: 4, uuid: uuid)], at: date).isEmpty)
        #expect(PowerOutputDiscovery.resolve([report], smc: [], connectors: [port(), port(id: "second")], at: date).isEmpty)
        #expect(PowerOutputDiscovery.resolve([report, report], smc: [], connectors: [port()], at: date).isEmpty)
        #expect(PowerOutputDiscovery.resolve([], smc: [channel, channel], connectors: [port(uuid: uuid)], at: date).isEmpty)
    }
    @Test func malformedUnitsAndRailReadingsCannotFabricatePower() {
        var wrong = report; wrong["Watts"] = 1000 // inconsistent with 5 V × 2 A
        #expect(PowerOutputDiscovery.resolve([wrong], smc: [], connectors: [port()], at: date).isEmpty)
        wrong = report; wrong["PortIndex"] = true
        #expect(PowerOutputDiscovery.resolve([wrong], smc: [], connectors: [port()], at: date).isEmpty)
        #expect(SMCInputReader.decodeUUID([UInt8](repeating: 0, count: 16)) == nil)
        #expect(SMCInputReader.decodeUUID([1]) == nil)
        #expect(PowerOutputDiscovery.normalizedUUID("11112222-3333-4444-5555-666677778888") == uuid)
        #expect(SMCInputReader.decodeOutput(uuid: uuid, volts: .infinity, amps: 1) == nil)
        #expect(SMCInputReader.decodeOutput(uuid: uuid, volts: 5, amps: -1) == nil)
    }
}
