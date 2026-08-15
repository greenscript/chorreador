import Foundation

enum WakePolicy: Equatable {
    case inactive
    case protectingSystem
    case protectingSystemAndDisplay
    case pausedForLowBattery

    static func evaluate(
        manualProtectionEnabled: Bool,
        automaticDetectionEnabled: Bool,
        hasDetectedAgent: Bool,
        letDisplaySleep: Bool,
        lowBatteryGuardEnabled: Bool,
        batteryPercentage: Int?,
        isOnBattery: Bool,
        lowBatteryThreshold: Int
    ) -> WakePolicy {
        let protectionRequested = manualProtectionEnabled
            || (automaticDetectionEnabled && hasDetectedAgent)
        guard protectionRequested else { return .inactive }

        if lowBatteryGuardEnabled,
           isOnBattery,
           let batteryPercentage,
           batteryPercentage <= lowBatteryThreshold {
            return .pausedForLowBattery
        }

        return letDisplaySleep ? .protectingSystem : .protectingSystemAndDisplay
    }
}
