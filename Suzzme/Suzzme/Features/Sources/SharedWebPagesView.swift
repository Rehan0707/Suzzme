import SwiftUI

struct SharedWebPagesView: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    @State private var pages: [SharedWebPage] = []
    @State private var message: String?
    @State private var configured = true
    @State private var unreadable = false
    @State private var confirmsClear = false
    @State private var askPage: SharedWebPage?
    @State private var sharedSource: SharedAppSource?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            pageList(at: timeline.date)
        }
        .suzzmeReadableList()
        .navigationTitle("Shared webpages")
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise", action: reload) }
        .task { reload() }
        .onChange(of: phase) { _, value in if value == .active { reload() } }
        .confirmationDialog("Clear shared URLs?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Clear shared URLs", role: .destructive) { perform { try SharedWebInbox().clear() } }
        } message: { Text("Only this temporary URL queue is cleared. Source pages, connected accounts, conversations and Personal Memory are kept.") }
        .sheet(item: $askPage) { page in
            AskSuzzmeView(initialText: "Explain this source: \(page.address)", focusInput: true, submitOnAppear: false)
        }
        .sheet(item: $sharedSource) { source in
            NavigationStack {
                SharedAppContextView(initialSource: source)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sharedSource = nil }.keyboardShortcut(.cancelAction) } }
            }
        }
    }
    private func pageList(at now: Date) -> some View {
        List {
            Section {
                Text("From Safari or another browser, choose Share → Suzme, then review the URL here. A shared URL grants no account access and contains no page text.")
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                Text("URLs expire after ten minutes. Expired files are removed on the next queue check; no exact background deletion time is promised.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            if !configured {
                Section { SuzzmeEmptyState(symbol: "square.and.arrow.down", title: "Sharing unavailable", message: SharedWebInboxError.unavailable.localizedDescription) }
            } else {
                    Section("Shared URLs") {
                        let fresh = pages.filter { $0.isFresh(at: now) }
                        if fresh.isEmpty { Text("No shared pages. Choose a URL in your browser’s Share menu to begin.").foregroundStyle(SuzzmeTheme.textSecondary) }
                        ForEach(fresh) { page in
                            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                                Text(page.address).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                Text(page.sharedAt, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                                Button("Open page in browser") { use(page) { openURL($0.url) } }
                                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                                if let resource = IntegrationResourceResolver.resolve(url: page.address), [.github, .notion].contains(resource.serviceID) {
                                    Button("Review a question about this link") { use(page) { askPage = $0 } }
                                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                                }
                                Button("Ask about text or a screenshot I choose") {
                                    use(page) { value in
                                        let host = value.url.host ?? ""
                                        sharedSource = host == "linkedin.com" || host.hasSuffix(".linkedin.com") ? .linkedin : .other
                                    }
                                }.frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                                Button("Remove URL", role: .destructive) { perform { _ = try SharedWebInbox().resolve(page); try SharedWebInbox().remove(page.id) } }
                                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                            }.padding(.vertical, SuzzmeTheme.Spacing.xs)
                        }
                    }
                if unreadable { Section { Text(SharedWebInboxError.malformed.localizedDescription).foregroundStyle(SuzzmeTheme.textSecondary) } }
                Section {
                    Text("Watched-page checking remains paused for network safety. Opening a URL in your browser does not share its contents with Suzme. Connected GitHub or Notion reads still require their own account permission and an explicit question.")
                        .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                    Button("Clear shared URLs…", role: .destructive) { confirmsClear = true }
                }
            }
            if let message { Section { Label(message, systemImage: "exclamationmark.circle"); Button("Try Again", action: reload) } }
        }
    }
    private func reload() {
        do {
            let result = try SharedWebInbox().pages()
            configured = true; pages = result.pages; unreadable = result.hasUnreadable; message = nil
        } catch {
            pages = []; configured = (error as? SharedWebInboxError) != .unavailable
            message = configured ? (error as? SharedWebInboxError)?.localizedDescription ?? SharedWebInboxError.storage.localizedDescription : nil
        }
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation(); reload() }
        catch { message = (error as? SharedWebInboxError)?.localizedDescription ?? SharedWebInboxError.storage.localizedDescription }
    }
    private func use(_ page: SharedWebPage, _ operation: (SharedWebPage) -> Void) {
        perform { operation(try SharedWebInbox().resolve(page)) }
    }
}
