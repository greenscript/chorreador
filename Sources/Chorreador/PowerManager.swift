import Foundation

@MainActor
final class PowerManager: NSObject, ObservableObject {
    static let lowBatteryThreshold = 20

    @Published var protectionEnabled: Bool {
        didSet {
            defaults.set(protectionEnabled, forKey: Keys.protectionEnabled)
            reconcilePolicy()
        }
    }

    @Published var letDisplaySleep: Bool {
        didSet {
            defaults.set(letDisplaySleep, forKey: Keys.letDisplaySleep)
            reconcilePolicy()
        }
    }

    @Published var automaticDetectionEnabled: Bool {
        didSet {
            defaults.set(automaticDetectionEnabled, forKey: Keys.automaticDetectionEnabled)
            refreshDetectedAgents()
        }
    }

    @Published var lowBatteryGuardEnabled: Bool {
        didSet {
            defaults.set(lowBatteryGuardEnabled, forKey: Keys.lowBatteryGuardEnabled)
            reconcilePolicy()
        }
    }

    @Published private(set) var battery = BatterySnapshot.unknown
    @Published private(set) var detectedAgents: Set<CodingAgent> = []
    @Published private(set) var policy = WakePolicy.inactive

    var isAutomaticallyProtecting: Bool {
        automaticDetectionEnabled && !detectedAgents.isEmpty
    }

    var protectionConfigured: Bool {
        protectionEnabled || automaticDetectionEnabled
    }

    private enum Keys {
        static let protectionEnabled = "protectionEnabled"
        static let letDisplaySleep = "letDisplaySleep"
        static let automaticDetectionEnabled = "automaticDetectionEnabled"
        static let lowBatteryGuardEnabled = "lowBatteryGuardEnabled"
        static let migratedLegacyPreferences = "migratedLegacyPreferences"
    }

    private let defaults: UserDefaults
    private var activity: NSObjectProtocol?
    private var batteryTimer: Timer?
    private var agentTimer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateLegacyPreferences(into: defaults)
        defaults.register(defaults: [
            Keys.protectionEnabled: false,
            Keys.letDisplaySleep: true,
            Keys.automaticDetectionEnabled: true,
            Keys.lowBatteryGuardEnabled: true
        ])

        protectionEnabled = defaults.bool(forKey: Keys.protectionEnabled)
        letDisplaySleep = defaults.bool(forKey: Keys.letDisplaySleep)
        automaticDetectionEnabled = defaults.bool(forKey: Keys.automaticDetectionEnabled)
        lowBatteryGuardEnabled = defaults.bool(forKey: Keys.lowBatteryGuardEnabled)

        super.init()
        refreshBattery()
        refreshDetectedAgents()
        batteryTimer = Timer.scheduledTimer(
            timeInterval: 30,
            target: self,
            selector: #selector(refreshBatteryFromTimer),
            userInfo: nil,
            repeats: true
        )
        agentTimer = Timer.scheduledTimer(
            timeInterval: 10,
            target: self,
            selector: #selector(refreshDetectedAgentsFromTimer),
            userInfo: nil,
            repeats: true
        )
    }

    deinit {
        batteryTimer?.invalidate()
        agentTimer?.invalidate()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
    }

    func refreshBattery() {
        battery = BatterySnapshot.current()
        reconcilePolicy()
    }

    func refreshDetectedAgents() {
        detectedAgents = automaticDetectionEnabled
            ? AgentProcessDetector.runningAgents()
            : []
        reconcilePolicy()
    }

    @objc private func refreshBatteryFromTimer() {
        refreshBattery()
    }

    @objc private func refreshDetectedAgentsFromTimer() {
        refreshDetectedAgents()
    }

    private func reconcilePolicy() {
        let nextPolicy = WakePolicy.evaluate(
            manualProtectionEnabled: protectionEnabled,
            automaticDetectionEnabled: automaticDetectionEnabled,
            hasDetectedAgent: !detectedAgents.isEmpty,
            letDisplaySleep: letDisplaySleep,
            lowBatteryGuardEnabled: lowBatteryGuardEnabled,
            batteryPercentage: battery.percentage,
            isOnBattery: battery.isOnBattery,
            lowBatteryThreshold: Self.lowBatteryThreshold
        )

        guard nextPolicy != policy else { return }
        endCurrentActivity()
        policy = nextPolicy

        switch nextPolicy {
        case .protectingSystem:
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled],
                reason: "Chorreador is keeping local agents flowing"
            )
        case .protectingSystemAndDisplay:
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled],
                reason: "Chorreador is keeping local agents and the display awake"
            )
        case .inactive, .pausedForLowBattery:
            break
        }
    }

    private func endCurrentActivity() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    private static func migrateLegacyPreferences(into defaults: UserDefaults) {
        guard defaults.object(forKey: Keys.migratedLegacyPreferences) == nil else { return }

        let preferenceKeys = [
            Keys.protectionEnabled,
            Keys.letDisplaySleep,
            Keys.automaticDetectionEnabled,
            Keys.lowBatteryGuardEnabled
        ]
        let legacySuiteNames = [
            "com.diegocano.agentpresso",
            "com.diegocano.wakeful"
        ]

        for suiteName in legacySuiteNames {
            if let legacyDefaults = UserDefaults(suiteName: suiteName) {
                for key in preferenceKeys where defaults.object(forKey: key) == nil {
                    if let value = legacyDefaults.object(forKey: key) {
                        defaults.set(value, forKey: key)
                    }
                }
            }
        }

        defaults.set(true, forKey: Keys.migratedLegacyPreferences)
    }
}
