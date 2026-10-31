import SwiftUI

struct WatchedLinksView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var presentsAdd = false
    @State private var confirmsReset = false
    @State private var pendingRemoval: WatchedLinkRecord?

    var body: some View {
        List {
            Section {
                Text(environment.watchedLinksAvailable
                    ? "Check only public HTTPS pages you explicitly choose. Saved pages from an earlier build need a new review before checking resumes."
                    : "Watched-page checking is paused for network safety. Your saved pages remain available to open or remove; Suzme sends no watched-page requests.")
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            }
            Section("Watched pages") {
                if environment.watchedLinks.isEmpty {
                    ContentUnavailableView("No Watched Links", systemImage: "link.badge.plus", description: Text(environment.watchedLinksAvailable
                        ? "Choose a public notice board, timetable or registration page. Review what checking permits before adding it."
                        : "New watched-page intake is paused until a connection-safe transport is available."))
                } else {
                    ForEach(environment.watchedLinks) { link in
                        WatchedLinkRow(link: link, onRemove: { pendingRemoval = link })
                            .swipeActions {
                                Button("Remove", role: .destructive) { pendingRemoval = link }
                            }
                    }
                }
            }
            if let error = environment.watchedLinkError {
                Section {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(SuzzmeTheme.textSecondary)
                    Button("Reset Watched Links…", role: .destructive) { confirmsReset = true }
                }
            }
            Section {
                Label("Page text is untrusted information. It cannot authorize actions, settings, or memory.", systemImage: "lock.shield")
                    .font(.footnote)
            } header: { Text("Safety") }
        }
        .suzzmeReadableList()
        .navigationTitle("Watched Links")
        .toolbar {
            Button("Add", systemImage: "plus") { presentsAdd = true }
                .disabled(!environment.watchedLinksAvailable)
                .accessibilityLabel(environment.watchedLinksAvailable ? "Add Watched Link" : "Watched Links paused for network safety")
        }
        .sheet(isPresented: $presentsAdd) { AddWatchedLinkView() }
        .confirmationDialog("Remove this Watched Link?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), titleVisibility: .visible) {
            if let link = pendingRemoval {
                Button("Remove \(link.name)", role: .destructive) { Task { await environment.removeWatchedLink(link); pendingRemoval = nil } }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { Text("Suzzme will stop checking this page and remove its stored updates. The current Daily Summary and opportunities will be cleared so they cannot retain those details.") }
        .confirmationDialog("Reset all Watched Links?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset Watched Links", role: .destructive) { Task { await environment.resetWatchedLinks() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes every watched page configuration and its stored updates, and clears the current Daily Summary and suggestions. Other sources and Personal Memory are kept. This cannot be undone.")
        }
        .task { await environment.loadWatchedLinks() }
    }
}

private struct WatchedLinkRow: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showsRecentChanges = false
    @State private var showsReview = false
    let link: WatchedLinkRecord
    let onRemove: () -> Void
    private var canOpenSource: Bool { (try? WebURLPolicy.validate(link.canonicalURL)) == link.canonicalURL }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(link.name).font(.headline)
                    Text(link.canonicalURL.host ?? link.canonicalURL.absoluteString).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary).lineLimit(1)
                }
                Spacer()
                Toggle("Watch \(link.name)", isOn: Binding(get: { link.permitsFetching }, set: { value in
                    if value { showsReview = true }
                    else { Task { await environment.setWatchedLinkEnabled(link, enabled: false) } }
                }))
                    .labelsHidden()
                    .disabled(!environment.watchedLinksAvailable && !link.permitsFetching)
                    .accessibilityHint("Turning checking on opens a review. Turning it off stops this page and withholds its derived updates.")
            }
            HStack {
                Label(stateTitle, systemImage: stateSymbol).font(.caption.weight(.medium)).foregroundStyle(stateColor)
                Spacer()
                if let date = link.lastSuccess { Text("Previously checked \(date, style: .relative)").font(.caption).foregroundStyle(SuzzmeTheme.textSecondary) }
            }
            Text(link.canonicalURL.absoluteString)
                .font(.caption)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let changedAt = link.lastMeaningfulChange {
                Text("Last meaningful change \(changedAt, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            }
            if !link.changes.isEmpty {
                Button {
                    showsRecentChanges.toggle()
                } label: {
                    Label("Recent meaningful details", systemImage: showsRecentChanges ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.medium))
                .frame(minHeight: SuzzmeTheme.Layout.touchTarget, alignment: .leading)
                .accessibilityValue(showsRecentChanges ? "Expanded" : "Collapsed")
                if showsRecentChanges {
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                        ForEach(link.changes) { change in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(change.title).font(.subheadline.weight(.semibold))
                                Text(change.detail).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                                Text("Observed \(change.observedAt, style: .relative)").font(.caption2).foregroundStyle(SuzzmeTheme.textSecondary)
                            }
                            if change.id != link.changes.last?.id { Divider() }
                        }
                    }
                    .padding(.top, SuzzmeTheme.Spacing.xs)
                }
            }
            SuzzmeActionControls {
                if environment.watchedLinksAvailable && !link.permitsFetching {
                    Button("Review and resume") { showsReview = true }
                        .accessibilityLabel("Review and resume checking \(link.name)")
                } else {
                    Button("Refresh") { Task { await environment.refreshWatchedLink(link) } }
                        .disabled(!environment.watchedLinksAvailable || !link.permitsFetching || link.state == .refreshing)
                }
                Link("Open Source", destination: link.canonicalURL)
                    .disabled(!canOpenSource)
                Button("Remove", role: .destructive, action: onRemove)
                    .accessibilityLabel("Remove Watched Link \(link.name)")
            }.buttonStyle(.bordered)
            if !canOpenSource {
                Text("This saved address no longer meets the public-page policy. Its history remains available to inspect or remove.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $showsReview) { ReviewWatchedLinkView(link: link) }
    }

    private var stateTitle: String {
        guard environment.watchedLinksAvailable else { return "Checking paused for safety" }
        guard link.permitsFetching else { return link.enabled ? "Review required" : "Off" }
        return switch link.state {
        case .ready: "Ready to check"
        case .disabled: "Off"
        case .refreshing: "Checking"
        case .unchanged: "No meaningful change"
        case .changed: "Change found"
        case .stale: "Refresh needed"
        case .offline: "Offline"
        case .unavailable: "Unavailable"
        case .blocked: "Blocked for safety"
        case .error: "Couldn’t check"
        }
    }
    private var stateSymbol: String {
        guard environment.watchedLinksAvailable else { return "pause.circle" }
        return !link.permitsFetching ? "hand.raised" : link.state == .changed ? "sparkles" : link.state == .blocked ? "hand.raised.fill" : "checkmark.circle"
    }
    private var stateColor: Color { link.permitsFetching && link.state == .changed ? SuzzmeTheme.intelligencePrimary : SuzzmeTheme.textSecondary }
}

private struct ReviewWatchedLinkView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    let link: WatchedLinkRecord
    private var supported: Bool { (try? WebURLPolicy.validate(link.canonicalURL)) == link.canonicalURL }

    var body: some View {
        NavigationStack {
            Form {
                Section("Page to check") {
                    Text(link.name).font(.headline)
                    Text(link.canonicalURL.absoluteString).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                WatchedLinkConsentDetails()
                if !supported {
                    Section { Text("This saved address no longer meets the public-page policy. You can keep its history or add a supported address separately.") }
                }
                if let error = environment.watchedLinkError { Section { Label(error, systemImage: "exclamationmark.circle") } }
                Section {
                    Button("Resume checking") {
                        Task {
                            isSaving = true
                            await environment.setWatchedLinkEnabled(link, enabled: true)
                            isSaving = false
                            if environment.watchedLinkError == nil { dismiss() }
                        }
                    }
                    .disabled(!supported || !environment.watchedLinksAvailable || isSaving)
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                    .accessibilityIdentifier("suzzme-watched-resume-confirm")
                }
            }
            .suzzmeSettingsForm()
            .navigationTitle("Review page checking")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) } }
        }
        .interactiveDismissDisabled(isSaving)
        #if os(macOS)
        .frame(minWidth: 360, idealWidth: 480, minHeight: 420)
        #endif
    }
}

private struct WatchedLinkConsentDetails: View {
    var body: some View {
        Section("What checking allows") {
            Text("Suzme requests this public page without cookies, account credentials or your browser session. Safe public redirects may be followed. Page text is extracted locally; scripts and linked files are not loaded.")
            Text("Checking is best-effort, with at least fifteen minutes between automatic checks. Saved change history may remain for thirty days; you can inspect or remove it at any time.")
                .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
        }
    }
}

private struct AddWatchedLinkView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Page") {
                    TextField("Name", text: $name)
                    TextField("https://example.edu/notices", text: $address)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                }
                WatchedLinkConsentDetails()
            }
            .suzzmeSettingsForm()
            .navigationTitle("Add Watched Link")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { isSaving = true; if await environment.addWatchedLink(name: name, url: address) { dismiss() }; isSaving = false } }
                        .disabled((try? WebURLPolicy.validate(address)) == nil || !environment.watchedLinksAvailable || isSaving)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 300)
        #endif
    }
}

#Preview("Watched Links — Empty") {
    NavigationStack { WatchedLinksView() }
        .environment(AppEnvironment.preview)
}

#Preview("Watched Link — Long Change") {
    List {
        WatchedLinkRow(link: .init(
            id: UUID(),
            name: "University timetable and registration notices",
            canonicalURL: URL(string: "https://example.edu/notices/timetable")!,
            enabled: true,
            state: .changed,
            etag: nil,
            lastModifiedHeader: nil,
            fingerprint: "preview",
            lastAttempt: .now,
            lastSuccess: .now,
            lastMeaningfulChange: .now,
            consecutiveFailures: 0,
            nextEligibleRefresh: nil,
            pageTitle: "University notices",
            changes: [.init(
                id: "preview-change",
                kind: .locationChange,
                title: "Operating Systems room changed",
                detail: "Tomorrow’s session moved from Room 302 to Lab 2. The source does not state another time change.",
                effectiveAt: .now.addingTimeInterval(86_400),
                effectiveUntil: nil,
                location: "Lab 2",
                observedAt: .now
            )]
        ), onRemove: {})
    }
    .environment(AppEnvironment.preview)
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility2)
}
