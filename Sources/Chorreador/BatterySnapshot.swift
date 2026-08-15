import Foundation
import IOKit.ps

struct BatterySnapshot: Equatable {
    let percentage: Int?
    let isOnBattery: Bool
    let isCharging: Bool

    static let unknown = BatterySnapshot(
        percentage: nil,
        isOnBattery: false,
        isCharging: false
    )

    static func current() -> BatterySnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .unknown
        }

        let powerType = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let isOnBattery = powerType == kIOPSBatteryPowerValue

        guard let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatterySnapshot(
                percentage: nil,
                isOnBattery: isOnBattery,
                isCharging: !isOnBattery
            )
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int,
                maximum > 0 else {
                continue
            }

            let percentage = Int((Double(current) / Double(maximum) * 100).rounded())
            let state = description[kIOPSPowerSourceStateKey] as? String
            let charging = (description[kIOPSIsChargingKey] as? Bool) == true
                || state == kIOPSACPowerValue

            return BatterySnapshot(
                percentage: percentage,
                isOnBattery: isOnBattery,
                isCharging: charging
            )
        }

        return BatterySnapshot(
            percentage: nil,
            isOnBattery: isOnBattery,
            isCharging: !isOnBattery
        )
    }
}
