import Foundation
import Testing
import PortAtlasCore
@testable import PortAtlasHardware

struct TelemetryTests {
    private let date = Date(timeIntervalSince1970: 1000)
    @Test func liveSMCInputReplacesSlowBatteryControllerReadings() {
        let smc = SMCInputReader.decode { ["PDTR": 42.5, "VD0R": 20, "ID0R": 2.1][$0] }
        let sample = PowerTelemetry.parse(["PowerTelemetryData": ["SystemPowerIn": 10000, "SystemVoltageIn": 19000], "ExternalConnected": true, "IsCharging": true],
            status: MacPowerStatus(externalPower: false, isCharging: false), at: date, smc: smc)
        #expect(sample.liveInput(at: date)?.value == 42.5)
        #expect(sample.input?.source == "AppleSMC.PDTR")
        #expect(sample.inputVoltage?.value == 20)
        #expect(sample.chargingLabel == "Charging")
    }
    @Test func smcNeverManufacturesZeroOrCombinesMissingRails() {
        #expect(SMCInputReader.decode { _ in nil } == nil)
        #expect(SMCInputReader.decode { _ in 0 } == nil)
        #expect(SMCInputReader.decode { ["VD0R": 20][$0] } == nil)
        #expect(SMCInputReader.decode { ["VD0R": 20, "ID0R": 2][$0] }?.watts == 40)
        #expect(SMCInputReader.decode { ["PDTR": .infinity, "VD0R": -20, "ID0R": 999][$0] } == nil)
        #expect(SMCInputReader.decode { ["VD0R": 60, "ID0R": 20][$0] } == nil)
        let source = SMCInputReader.decode { ["PDTR": 10][$0] }
        let sample = PowerTelemetry.parse([:], status: MacPowerStatus(externalPower: true), at: date, smc: source)
        #expect(sample.input?.value == 10)
        #expect(sample.inputVoltage == nil && sample.inputCurrent == nil)
        let unplugged = PowerTelemetry.parse(["ExternalConnected": false], status: MacPowerStatus(externalPower: true), at: date, smc: source)
        #expect(unplugged.input == nil)
        #expect(unplugged.status.externalPower == false)
    }
    @Test func smcFloatDecoderRejectsUnknownPayloads() {
        #expect(SMCInputReader.decodeFloat([0, 0, 32, 65]) == 10)
        #expect(SMCInputReader.decodeFloat([0, 0, 128, 127]) == nil) // infinity
        #expect(SMCInputReader.decodeFloat([0, 0]) == nil)
        #expect(SMCInputReader.fourCC("PDTR") == 0x50445452)
        #expect(SMCInputReader.fourCC("INVALID") == nil)
    }
    @Test func invalidStatusFlagsDoNotOverridePowerSourceAPI() {
        let status = PowerDiscovery.status(overriding: MacPowerStatus(externalPower: true, isCharging: true),
            battery: ["ExternalConnected": "false", "IsCharging": 2])
        #expect(status.externalPower == true && status.isCharging == true)
    }
    @Test func inputHasSystemScopeAndCorrectUnits() {
        let sample = PowerTelemetry.parse(["PowerTelemetryData": ["SystemPowerIn": 15881, "SystemVoltageIn": 20026, "SystemCurrentIn": 793],
            "CurrentCapacity": 85, "Voltage": 12000, "Amperage": 1000],
            status: MacPowerStatus(externalPower: true, isCharging: true, adapterWatts: 100), at: date)
        #expect(sample.input?.value == 15.881)
        #expect(sample.input?.scope == .macInput)
        #expect(sample.inputVoltage?.value == 20.026)
        #expect(sample.inputCurrent?.value == 0.793)
        #expect(sample.battery?.value == 12)
        #expect(sample.status.adapterWatts == 100)
        #expect(sample.batteryPercent == 85)
    }
    @Test func batteryPowerUsesSignedCurrentAndDoesNotBecomeInput() {
        let sample = PowerTelemetry.parse(["Voltage": 12000, "Amperage": NSNumber(value: UInt64.max - 999),
            "PowerTelemetryData": ["SystemPowerIn": 15000]], status: MacPowerStatus(externalPower: false), at: date)
        #expect(sample.battery?.value == -12)
        #expect(sample.input == nil)
    }
    @Test func missingInvalidAndBooleanReadingsAreNotZero() {
        let missing = PowerTelemetry.parse([:], status: MacPowerStatus(externalPower: true), at: date)
        #expect(missing.input == nil && missing.batteryPercent == nil)
        let invalid = PowerTelemetry.parse(["PowerTelemetryData": ["SystemPowerIn": true, "SystemVoltageIn": -1, "SystemCurrentIn": 999999], "CurrentCapacity": 120],
            status: MacPowerStatus(externalPower: true), at: date)
        #expect(invalid.input == nil && invalid.inputVoltage == nil && invalid.inputCurrent == nil && invalid.batteryPercent == nil)
        let zero = PowerTelemetry.parse(["PowerTelemetryData": ["SystemPowerIn": 0]], status: MacPowerStatus(externalPower: true), at: date)
        #expect(zero.input?.value == 0)
    }
    @Test func staleReadingsAreUnavailableAndHistoryIsBounded() {
        var history = PowerHistory()
        for second in 0...120 {
            let timestamp = date.addingTimeInterval(Double(second))
            let sample = PowerTelemetry.parse(["PowerTelemetryData": ["SystemPowerIn": 10000]], status: MacPowerStatus(externalPower: true), at: timestamp)
            history.append(sample)
        }
        #expect(history.samples.count == 61)
        let last = history.samples.last!
        #expect(last.liveInput(at: last.sampledAt.addingTimeInterval(6)) == nil)
        #expect(last.liveInput(at: last.sampledAt.addingTimeInterval(2))?.value == 10)
        history.append(PowerSample(sampledAt: date.addingTimeInterval(121), status: MacPowerStatus(externalPower: false)))
        #expect(history.samples.count == 1)
    }
    @Test func batteryOrContractReadingsCannotBeDisplayedAsMacInput() {
        let battery = PowerMeasurement(value: 30, unit: .watts, scope: .battery, source: "fixture", sampledAt: date)
        let sample = PowerSample(sampledAt: date, status: MacPowerStatus(externalPower: true), input: battery)
        #expect(sample.liveInput(at: date) == nil)
        let voltage = PowerMeasurement(value: 20, unit: .volts, scope: .macInput, source: "fixture", sampledAt: date)
        #expect(PowerSample(status: MacPowerStatus(externalPower: true), input: voltage).liveInput(at: date) == nil)
    }
    @Test func networkLinkRequiresValidActiveStatusAndIsIndependentOfUSB() {
        let connected = NetworkTelemetry.parse(["IOLinkStatus": 3, "IOLinkSpeed": 2500000000], id: "fixture", deviceID: "device", at: date)
        #expect(connected.bitsPerSecond == 2500000000)
        #expect(connected.label == "Ethernet · 2.5 Gb/s")
        let disconnected = NetworkTelemetry.parse(["IOLinkStatus": 1, "IOLinkSpeed": 2500000000], id: "fixture", deviceID: "device", at: date)
        #expect(disconnected.isActive == false && disconnected.bitsPerSecond == nil)
        let unknown = NetworkTelemetry.parse(["IOLinkStatus": 2], id: "fixture", deviceID: "device", at: date)
        #expect(unknown.isActive == nil)
        let invalid = NetworkTelemetry.parse(["IOLinkStatus": -1, "IOLinkSpeed": true], id: "fixture", deviceID: "device", at: date)
        #expect(invalid.isActive == nil && invalid.bitsPerSecond == nil)
    }
    @Test func cableIdentityRequiresExactlyOneCablePlug() {
        let sop: [String: Any] = ["ComponentName": "SOP'", "Metadata": ["Product Type Description": "Passive Cable"], "Specification Revision": 3]
        #expect(PowerDiscovery.parseCable([sop])?.pdRevision == 3)
        #expect(PowerDiscovery.parseCable([sop, sop]) == nil)
        #expect(PowerDiscovery.parseCable([["ComponentName": "SOP", "Metadata": ["Product Type Description": "Passive Cable"]]]) == nil)
    }
}
