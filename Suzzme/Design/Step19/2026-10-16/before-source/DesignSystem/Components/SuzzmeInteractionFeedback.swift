import SwiftUI

#if os(iOS)
import UIKit
import CoreHaptics
#elseif os(macOS)
import AppKit
#endif

/// Discrete feedback from real interactions, never from animation frames.
@MainActor
enum SuzzmeHaptics {
    enum Event { case activation, recordingStarted, recordingStopped, success, confirmation, invalid, selection, completion }
    static let preferenceKey = "suzzme.haptics.enabled"

    static var isSupported: Bool {
        #if os(iOS)
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
        #else
        false
        #endif
    }

    static func play(_ event: Event) {
        guard UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true else { return }
        #if os(iOS)
        guard isSupported else { return }
        // UIKit observes the device's system feedback settings. No custom engine,
        // audio session or simulated hardware feedback is created.
        switch event {
        case .activation:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
        case .recordingStarted, .recordingStopped:
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.4)
        case .success, .completion:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .confirmation:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.4)
        case .invalid:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        }
        #elseif os(macOS)
        // AppKit routes this best-effort request to eligible hardware. A Mac
        // without a haptic trackpad still receives the existing visual status.
        switch event {
        case .confirmation:
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        case .success, .completion:
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        default:
            break
        }
        #endif
    }
}

private struct SuzzmeInteractionFeedback: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let state: SuzzmeAssistantState
    let isRecording: Bool
    let confirmationID: UUID?

    func body(content: Content) -> some View {
        content
            .onChange(of: state) { previous, current in
                guard scenePhase == .active else { return }
                switch current {
                case .understanding where previous == .idle: SuzzmeHaptics.play(.activation)
                case .success: SuzzmeHaptics.play(.completion)
                case .error: SuzzmeHaptics.play(.invalid)
                default: break
                }
            }
            .onChange(of: isRecording) { _, recording in
                guard scenePhase == .active else { return }
                SuzzmeHaptics.play(recording ? .recordingStarted : .recordingStopped)
            }
            .onChange(of: confirmationID) { _, confirmation in
                guard scenePhase == .active, confirmation != nil else { return }
                SuzzmeHaptics.play(.confirmation)
            }
    }
}

extension View {
    func suzzmeInteractionFeedback(state: SuzzmeAssistantState, isRecording: Bool, confirmationID: UUID?) -> some View {
        modifier(SuzzmeInteractionFeedback(state: state, isRecording: isRecording, confirmationID: confirmationID))
    }

    func suzzmeSelectionFeedback<Value: Equatable>(trigger: Value) -> some View {
        onChange(of: trigger) { _, _ in SuzzmeHaptics.play(.selection) }
    }
}
