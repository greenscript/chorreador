import AppKit
import Foundation
import ServiceManagement

@MainActor
final class PowerManager: NSObject, ObservableObject {
    nonisolated static let lowBatteryThreshold = 20

    let journal: PourJournal

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

    @Published private(set) var notificationsEnabled: Bool
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var launchAtLoginNeedsApproval: Bool
    @Published private(set) var customProcessNames: [String]

    @Published private(set) var battery = BatterySnapshot.unknown
    @Published private(set) var detectedAgents: Set<CodingAgent> = []
    @Published private(set) var detectedCustomProcesses: Set<String> = []
    @Published private(set) var policy = WakePolicy.inactive
    @Published private(set) var brewTimerEndDate: Date?
    @Published private(set) var pourStartedAt: Date?

    var isAutomaticallyProtecting: Bool {
        automaticDetectionEnabled
            && (!detectedAgents.isEmpty || !detectedCustomProcesses.isEmpty)
    }

    var protectionConfigured: Bool {
        protectionEnabled || automaticDetectionEnabled || brewTimerEndDate != nil
    }

    var detectedProcessDisplayNames: [String] {
        detectedAgents
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
            + detectedCustomProcesses.sorted()
    }

    private enum Keys {
        static let protectionEnabled = "protectionEnabled"
        static let letDisplaySleep = "letDisplaySleep"
        static let automaticDetectionEnabled = "automaticDetectionEnabled"
        static let lowBatteryGuardEnabled = "lowBatteryGuardEnabled"
        static let notificationsEnabled = "notificationsEnabled"
        static let customProcessNames = "customProcessNames"
        static let brewTimerEndDate = "brewTimerEndDate"
        static let migratedLegacyPreferences = "migratedLegacyPreferences"
    }

    private let defaults: UserDefaults
    private var activity: NSObjectProtocol?
    private var batteryTimer: Timer?
    private var agentTimer: Timer?
    private var brewTimer: Timer?
    private var agentScanTask: Task<Void, Never>?
    private var hasCompletedInitialAgentScan = false
    private var pourSleptAt: Date?

    init(defaults: UserDefaults = .standard, journal: PourJournal? = nil) {
        self.defaults = defaults
        self.journal = journal ?? PourJournal()
        Self.migrateLegacyPreferences(into: defaults)
        defaults.register(defaults: [
            Keys.protectionEnabled: false,
            Keys.letDisplaySleep: true,
            Keys.automaticDetectionEnabled: true,
            Keys.lowBatteryGuardEnabled: true,
            Keys.notificationsEnabled: false,
            Keys.customProcessNames: []
        ])

        protectionEnabled = defaults.bool(forKey: Keys.protectionEnabled)
        letDisplaySleep = defaults.bool(forKey: Keys.letDisplaySleep)
        automaticDetectionEnabled = defaults.bool(forKey: Keys.automaticDetectionEnabled)
        lowBatteryGuardEnabled = defaults.bool(forKey: Keys.lowBatteryGuardEnabled)
        notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        customProcessNames = defaults.stringArray(forKey: Keys.customProcessNames) ?? []

        let loginStatus = SMAppService.mainApp.status
        launchAtLoginEnabled = loginStatus == .enabled
        launchAtLoginNeedsApproval = loginStatus == .requiresApproval

        if let storedEndDate = defaults.object(forKey: Keys.brewTimerEndDate) as? Date,
           storedEndDate > Date() {
            brewTimerEndDate = storedEndDate
        } else {
            brewTimerEndDate = nil
            defaults.removeObject(forKey: Keys.brewTimerEndDate)
        }

        super.init()
        scheduleBrewTimerIfNeeded()
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

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(workspaceWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    deinit {
        batteryTimer?.invalidate()
        agentTimer?.invalidate()
        brewTimer?.invalidate()
        agentScanTask?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
    }

    @objc private func workspaceWillSleep() {
        guard policy == .protectingSystem || policy == .protectingSystemAndDisplay else { return }
        pourSleptAt = Date()
    }

    @objc private func workspaceDidWake() {
        defer {
            refreshBattery()
            refreshDetectedAgents()
        }
        guard let sleptAt = pourSleptAt else { return }
        pourSleptAt = nil

        let wokeAt = Date()
        journal.recordInterruption(sleptAt: sleptAt, wokeAt: wokeAt)

        if notificationsEnabled {
            let sources = journal.openRecord?.sources ?? currentPourSources
            NotificationManager.send(
                title: "The pour was interrupted",
                body: "Your Mac slept \(brewDurationText(wokeAt.timeIntervalSince(sleptAt))) while \(sources.joined(separator: " + ")) was flowing."
            )
        }
    }

    func refreshBattery() {
        battery = BatterySnapshot.current()
        reconcilePolicy()
    }

    func refreshDetectedAgents() {
        agentScanTask?.cancel()

        guard automaticDetectionEnabled else {
            applyAgentDetection(AgentDetectionResult(agents: [], customProcesses: []))
            return
        }

        let processNames = customProcessNames
        agentScanTask = Task { [weak self] in
            let detection = await Task.detached(priority: .utility) {
                AgentProcessDetector.runningDetection(customProcessNames: processNames)
            }.value

            guard !Task.isCancelled,
                  let self,
                  self.automaticDetectionEnabled else { return }
            self.applyAgentDetection(detection)
        }
    }

    private func applyAgentDetection(_ detection: AgentDetectionResult) {
        let previousNames = detectedProcessDisplayNames
        detectedAgents = detection.agents
        detectedCustomProcesses = detection.customProcesses
        reconcilePolicy()

        if pourStartedAt != nil {
            journal.updateSources(currentPourSources, at: Date())
        }

        let currentNames = detectedProcessDisplayNames
        if hasCompletedInitialAgentScan {
            notifyAgentTransition(from: previousNames, to: currentNames)
        } else {
            hasCompletedInitialAgentScan = true
        }
    }

    func startBrewTimer(_ option: BrewTimerOption) {
        brewTimerEndDate = Date().addingTimeInterval(option.duration)
        defaults.set(brewTimerEndDate, forKey: Keys.brewTimerEndDate)
        scheduleBrewTimerIfNeeded()
        reconcilePolicy()
    }

    func cancelBrewTimer() {
        brewTimer?.invalidate()
        brewTimer = nil
        brewTimerEndDate = nil
        defaults.removeObject(forKey: Keys.brewTimerEndDate)
        reconcilePolicy()
    }

    func addCustomProcess(_ processName: String) {
        // Stored verbatim: entries with "/" or spaces are command-line patterns,
        // so collapsing them to a basename would break them.
        let normalized = processName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        guard !customProcessNames.contains(where: {
            $0.caseInsensitiveCompare(normalized) == .orderedSame
        }) else { return }

        customProcessNames.append(normalized)
        customProcessNames.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        defaults.set(customProcessNames, forKey: Keys.customProcessNames)
        refreshDetectedAgents()
    }

    func removeCustomProcess(_ processName: String) {
        customProcessNames.removeAll {
            $0.caseInsensitiveCompare(processName) == .orderedSame
        }
        defaults.set(customProcessNames, forKey: Keys.customProcessNames)
        refreshDetectedAgents()
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        guard enabled else {
            notificationsEnabled = false
            defaults.set(false, forKey: Keys.notificationsEnabled)
            return
        }

        NotificationManager.requestAuthorization { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.notificationsEnabled = granted
                self.defaults.set(granted, forKey: Keys.notificationsEnabled)
            }
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // The status below remains the source of truth if macOS rejects the change.
        }
        refreshLaunchAtLoginStatus()
    }

    func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    private var currentPourSources: [String] {
        let names = detectedProcessDisplayNames
        if !names.isEmpty { return names }
        if protectionEnabled { return ["Manual pour"] }
        if brewTimerEndDate != nil { return ["Brew timer"] }
        return ["Manual pour"]
    }

    @objc private func refreshBatteryFromTimer() {
        refreshBattery()
        if pourStartedAt != nil {
            journal.keepAlive(at: Date())
        }
    }

    @objc private func refreshDetectedAgentsFromTimer() {
        refreshDetectedAgents()
    }

    @objc private func finishBrewTimer() {
        cancelBrewTimer()
    }

    private func reconcilePolicy() {
        let nextPolicy = WakePolicy.evaluate(
            manualProtectionEnabled: protectionEnabled || brewTimerEndDate != nil,
            automaticDetectionEnabled: automaticDetectionEnabled,
            hasDetectedAgent: !detectedAgents.isEmpty || !detectedCustomProcesses.isEmpty,
            letDisplaySleep: letDisplaySleep,
            lowBatteryGuardEnabled: lowBatteryGuardEnabled,
            batteryPercentage: battery.percentage,
            isOnBattery: battery.isOnBattery,
            lowBatteryThreshold: Self.lowBatteryThreshold
        )

        guard nextPolicy != policy else { return }
        let previousPolicy = policy
        endCurrentActivity()
        policy = nextPolicy

        if nextPolicy == .protectingSystem || nextPolicy == .protectingSystemAndDisplay {
            if pourStartedAt == nil {
                let startedAt = Date()
                pourStartedAt = startedAt
                journal.beginPour(at: startedAt, sources: currentPourSources)
            }
        } else {
            if pourStartedAt != nil {
                journal.endPour(
                    at: Date(),
                    reason: nextPolicy == .pausedForLowBattery ? .batteryPause : .finished
                )
            }
            pourStartedAt = nil
        }

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

        if previousPolicy != .pausedForLowBattery,
           nextPolicy == .pausedForLowBattery,
           notificationsEnabled {
            NotificationManager.send(
                title: "Chorreador is resting",
                body: "Battery care paused the pour at \(Self.lowBatteryThreshold)%."
            )
        }
    }

    private func scheduleBrewTimerIfNeeded() {
        brewTimer?.invalidate()
        guard let brewTimerEndDate else { return }

        let remaining = brewTimerEndDate.timeIntervalSinceNow
        guard remaining > 0 else {
            cancelBrewTimer()
            return
        }
        brewTimer = Timer.scheduledTimer(
            timeInterval: remaining,
            target: self,
            selector: #selector(finishBrewTimer),
            userInfo: nil,
            repeats: false
        )
    }

    private func notifyAgentTransition(from previous: [String], to current: [String]) {
        guard notificationsEnabled, previous != current else { return }

        if previous.isEmpty, !current.isEmpty {
            NotificationManager.send(
                title: "The pour has started",
                body: "\(current.joined(separator: " + ")) detected. Your Mac will stay awake."
            )
        } else if !previous.isEmpty, current.isEmpty {
            NotificationManager.send(
                title: "The pour has finished",
                body: "No coding agents are running. Normal sleep behavior has resumed."
            )
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
