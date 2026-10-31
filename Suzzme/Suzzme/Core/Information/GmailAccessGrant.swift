import Foundation
import CryptoKit

/// Ephemeral credentials; never serialized into the information store.
struct GmailAccessGrant: Sendable {
    let token: String
    let accountNamespace: String
    let generation: UUID

    static func namespace(for accountID: String) -> String {
        "gmail:" + SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined() + ":"
    }

    func owns(_ externalID: String) -> Bool { externalID.hasPrefix(accountNamespace) }
}

protocol GmailAuthorizationProviding: Sendable {
    func authorization() async -> InformationHealthState
    func accessGrant() async throws -> GmailAccessGrant
    func validate(_ grant: GmailAccessGrant) async throws
    func invalidate(_ grant: GmailAccessGrant, state: InformationHealthState) async
    func gmailSelection() async -> GmailSelection?
    func gmailBodyAccess() async -> Bool
    func permitsGmailEvent(_ event: InformationEvent) async -> Bool
}

extension GmailAuthorizationProviding {
    func gmailSelection() async -> GmailSelection? { .init(mode: .recentInbox, generation: UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1))) }
    func gmailBodyAccess() async -> Bool { false }
}
