import Foundation
import EventKit
import Contacts

enum SuzzmePermissionState: String, Sendable {
    case notDetermined, authorized, denied, restricted, unavailable
    var displayName: String {
        switch self { case .notDetermined: "Not connected"; case .authorized: "Connected"; case .denied: "Access off"; case .restricted: "Unavailable"; case .unavailable: "Unavailable" }
    }
}

actor AppleContextPermissions {
    private let eventStore: EKEventStore
    private let contactStore: CNContactStore

    init(eventStore: EKEventStore = EKEventStore(), contactStore: CNContactStore = CNContactStore()) {
        self.eventStore = eventStore; self.contactStore = contactStore
    }

    func status(for kind: SuzzmeContextSourceKind) -> SuzzmePermissionState {
        switch kind {
        case .calendar: Self.eventStatus(EKEventStore.authorizationStatus(for: .event))
        case .reminders: Self.eventStatus(EKEventStore.authorizationStatus(for: .reminder))
        case .contacts: Self.contactStatus(CNContactStore.authorizationStatus(for: .contacts))
        }
    }

    func request(_ kind: SuzzmeContextSourceKind) async -> SuzzmePermissionState {
        guard status(for: kind) == .notDetermined else { return status(for: kind) }
        do {
            switch kind {
            case .calendar:
                if #available(iOS 17.0, macOS 14.0, *) { _ = try await eventStore.requestFullAccessToEvents() }
            case .reminders:
                if #available(iOS 17.0, macOS 14.0, *) { _ = try await eventStore.requestFullAccessToReminders() }
            case .contacts:
                _ = try await contactStore.requestAccess(for: .contacts)
            }
        } catch { }
        return status(for: kind)
    }

    private static func eventStatus(_ status: EKAuthorizationStatus) -> SuzzmePermissionState {
        switch status { case .notDetermined: .notDetermined; case .fullAccess: .authorized; case .denied: .denied; case .restricted: .restricted; @unknown default: .unavailable }
    }
    private static func contactStatus(_ status: CNAuthorizationStatus) -> SuzzmePermissionState {
        switch status { case .notDetermined: .notDetermined; case .authorized: .authorized; case .denied: .denied; case .restricted: .restricted; @unknown default: .unavailable }
    }
}
