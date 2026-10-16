import Testing
@testable import PortAtlasHardware

struct PowerDiscoveryTests {
    @Test func maximumSpeedUsesPhysicalSocketAndSupportedMask() {
        let report = TransportDiscovery.maximumLinkSpeed(["Description": "Thunderbolt Port", "Socket ID": "4", "Supported Link Speed": 12, "Supported Link Width": 2, "Current Link Speed": 0])
        #expect(report?.number == 4)
        #expect(report?.speed.megabitsPerSecond == 40000)
        #expect(TransportDiscovery.maximumLinkSpeed(["Description": "USB Adapter", "Socket ID": "4", "Supported Link Speed": 14, "Supported Link Width": 2]) == nil)
        #expect(TransportDiscovery.maximumLinkSpeed(["Description": "Thunderbolt Port", "Socket ID": "4", "Supported Link Speed": true, "Supported Link Width": 2]) == nil)
        #expect(TransportDiscovery.maximumLinkSpeed(["Description": "Thunderbolt Port", "Socket ID": "", "Supported Link Speed": 12, "Supported Link Width": 2]) == nil)
    }
    @Test func advertisedPDOIsNeverASelectedContract() {
        let result = PowerDiscovery.parseSources([["PowerSourceName": "USB-PD", "PowerSourceOptions": [
            ["Max Power (mW)": 60000], ["Max Power (mW)": 140000]
        ]]])
        #expect(result?.advertisedWatts == 140)
        #expect(result?.contractWatts == nil)
        #expect(result?.voltageMillivolts == nil)
    }
    @Test func selectedPDValuesRetainUnitsAndDoNotUseHighestOffer() {
        let result = PowerDiscovery.parseSources([["PowerSourceName": "USB-PD",
            "WinningPowerSourceOption": ["Max Power (mW)": 60000, "Voltage (mV)": 20000, "Max Current (mA)": 3000],
            "PowerSourceOptions": [["Max Power (mW)": 100000]]]])
        #expect(result?.contractWatts == 60)
        #expect(result?.voltageMillivolts == 20000)
        #expect(result?.currentMilliamps == 3000)
        #expect(result?.advertisedWatts == 100)
    }
    @Test func conflictingSourcesAndUnsupportedSupplyAreOmitted() {
        let source: [String: Any] = ["PowerSourceName": "USB-PD", "WinningPowerSourceOption": ["Max Power (mW)": 60000]]
        #expect(PowerDiscovery.parseSources([source, source]) == nil)
        #expect(PowerDiscovery.parseSources([["PowerSourceName": "Brick ID"]]) == nil)
        #expect(PowerDiscovery.parseSources([["PowerSourceName": "USB-PD", "WinningPowerSourceOption": ["Max Power (mW)": -1]]])?.contractWatts == nil)
    }
}
