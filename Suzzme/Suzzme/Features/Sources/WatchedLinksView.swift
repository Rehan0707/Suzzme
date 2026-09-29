import SwiftUI

struct WatchedLinksView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var presentsAdd = false
    @State private var confirmsReset = false
    @State private var pendingRemoval: WatchedLinkRecord?

    var body: some View {
        List {
            Section {
                Text("Pages you ask Suzzme to watch for meaningful changes. Only the page you choose is checked.")
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            }
            Section("Watched pages") {
                if environment.watchedLinks.isEmpty {
                    ContentUnavailableView("No Watched Links", systemImage: "link.badge.plus", description: Text("Add a timetable, notice board, or registration page you want Suzzme to check."))
                } else {
                    ForEach(environment.watchedLinks) { link in
                        WatchedLinkRow(link: link)
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
        .navigationTitle("Watched Links")
        .toolbar { Button("Add", systemImage: "plus") { presentsAdd = true }.accessibilityLabel("Add Watched Link") }
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
    let link: WatchedLinkRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(link.name).font(.headline)
                    Text(link.canonicalURL.host ?? link.canonicalURL.absoluteString).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary).lineLimit(1)
                }
                Spacer()
                Toggle("Watch \(link.name)", isOn: Binding(get: { link.enabled }, set: { value in Task { await environment.setWatchedLinkEnabled(link, enabled: value) } }))
                    .labelsHidden()
            }
            HStack {
                Label(stateTitle, systemImage: stateSymbol).font(.caption.weight(.medium)).foregroundStyle(stateColor)
                Spacer()
                if let date = link.lastSuccess { Text("Checked \(date, style: .relative)").font(.caption).foregroundStyle(SuzzmeTheme.textSecondary) }
            }
            Text("Exact page · \(link.canonicalURL.path.isEmpty ? "/" : link.canonicalURL.path)")
                .font(.caption)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .lineLimit(1)
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
                .accessibilityValue(showsRecentChanges ? "Expanded" : "Collapsed")
                if showsRecentChanges {
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                        ForEach(link.changes.prefix(5)) { change in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(change.title).font(.subheadline.weight(.semibold))
                                Text(change.detail).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                                Text("Observed \(change.observedAt, style: .relative)").font(.caption2).foregroundStyle(SuzzmeTheme.textSecondary)
                            }
                            if change.id != link.changes.prefix(5).last?.id { Divider() }
                        }
                    }
                    .padding(.top, SuzzmeTheme.Spacing.xs)
                }
            }
            SuzzmeActionControls {
                Button("Refresh") { Task { await environment.refreshWatchedLink(link) } }.disabled(!link.enabled || link.state == .refreshing)
                Link("Open Source", destination: link.canonicalURL)
            }.buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }

    private var stateTitle: String {
        switch link.state {
        case .ready: "Ready"
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
    private var stateSymbol: String { link.state == .changed ? "sparkles" : link.state == .offline ? "wifi.slash" : link.state == .blocked ? "hand.raised.fill" : "checkmark.circle" }
    private var stateColor: Color { link.state == .changed ? SuzzmeTheme.intelligencePrimary : link.state == .blocked || link.state == .error ? .orange : SuzzmeTheme.textSecondary }
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
                Section { Text("Suzzme checks this exact public page only. Sign-in pages, local addresses, file URLs, and private networks are not supported.") }
            }
            .navigationTitle("Add Watched Link")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { isSaving = true; if await environment.addWatchedLink(name: name, url: address) { dismiss() }; isSaving = false } }
                        .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 300)
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
        ))
    }
    .environment(AppEnvironment.preview)
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility2)
}
