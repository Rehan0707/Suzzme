import SwiftUI

/// Compatibility entry point for older navigation paths. Gmail authorization now
/// uses the same Composio-hosted sign-in and verified account flow as other apps.
struct GmailConnectionView: View {
    var body: some View {
        ComposioIntegrationsView(initialServiceID: "gmail")
    }
}
