import XCTest
@testable import Chorreador

final class WakePolicyTests: XCTestCase {
    func testDisabledProtectionIsInactive() {
        XCTAssertEqual(
            evaluate(enabled: false, displaySleep: true, percentage: 80, onBattery: true),
            .inactive
        )
    }

    func testRecommendedModeProtectsSystemOnly() {
        XCTAssertEqual(
            evaluate(enabled: true, displaySleep: true, percentage: 80, onBattery: true),
            .protectingSystem
        )
    }

    func testOptionalModeAlsoProtectsDisplay() {
        XCTAssertEqual(
            evaluate(enabled: true, displaySleep: false, percentage: 80, onBattery: true),
            .protectingSystemAndDisplay
        )
    }

    func testLowBatteryPausesProtectionAtThreshold() {
        XCTAssertEqual(
            evaluate(enabled: true, displaySleep: true, percentage: 20, onBattery: true),
            .pausedForLowBattery
        )
    }

    func testLowBatteryDoesNotPauseWhileConnectedToPower() {
        XCTAssertEqual(
            evaluate(enabled: true, displaySleep: true, percentage: 10, onBattery: false),
            .protectingSystem
        )
    }

    func testGuardCanBeDisabled() {
        XCTAssertEqual(
            evaluate(enabled: true, displaySleep: true, guardEnabled: false, percentage: 10, onBattery: true),
            .protectingSystem
        )
    }

    func testDetectedAgentAutomaticallyEnablesProtection() {
        XCTAssertEqual(
            evaluate(
                enabled: false,
                autoDetection: true,
                agentDetected: true,
                displaySleep: true,
                percentage: 80,
                onBattery: true
            ),
            .protectingSystem
        )
    }

    func testAutoDetectionWithoutAgentRemainsInactive() {
        XCTAssertEqual(
            evaluate(
                enabled: false,
                autoDetection: true,
                agentDetected: false,
                displaySleep: true,
                percentage: 80,
                onBattery: true
            ),
            .inactive
        )
    }

    private func evaluate(
        enabled: Bool,
        autoDetection: Bool = false,
        agentDetected: Bool = false,
        displaySleep: Bool,
        guardEnabled: Bool = true,
        percentage: Int?,
        onBattery: Bool
    ) -> WakePolicy {
        WakePolicy.evaluate(
            manualProtectionEnabled: enabled,
            automaticDetectionEnabled: autoDetection,
            hasDetectedAgent: agentDetected,
            letDisplaySleep: displaySleep,
            lowBatteryGuardEnabled: guardEnabled,
            batteryPercentage: percentage,
            isOnBattery: onBattery,
            lowBatteryThreshold: 20
        )
    }
}
