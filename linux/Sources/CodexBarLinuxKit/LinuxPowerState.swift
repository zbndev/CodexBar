import Foundation

public enum LinuxPowerState: Equatable, Sendable {
    case nominal
    case constrained

    public static func current(sysfsRoot: URL = URL(fileURLWithPath: "/sys")) -> Self {
        let powerSupplyRoot = sysfsRoot.appendingPathComponent("class/power_supply")
        if self.hasConstrainedBattery(in: powerSupplyRoot) { return .constrained }

        let thermalRoot = sysfsRoot.appendingPathComponent("class/thermal")
        if self.hasConstrainedThermalZone(in: thermalRoot) { return .constrained }
        return .nominal
    }

    private static func hasConstrainedBattery(in root: URL) -> Bool {
        self.directoryContents(of: root).contains { battery in
            let status = self.string(at: battery.appendingPathComponent("status"))
            let capacity = self.string(at: battery.appendingPathComponent("capacity")).flatMap(Int.init)
            return status == "Discharging" && (capacity ?? 101) <= 20
        }
    }

    private static func hasConstrainedThermalZone(in root: URL) -> Bool {
        self.directoryContents(of: root).contains { zone in
            guard zone.lastPathComponent.hasPrefix("thermal_zone"),
                  let temperature = self.string(at: zone.appendingPathComponent("temp")).flatMap(Int.init)
            else { return false }
            return temperature >= 85_000
        }
    }

    private static func directoryContents(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
    }

    private static func string(at url: URL) -> String? {
        guard let value = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
