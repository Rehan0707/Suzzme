import SwiftUI

struct MemoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var memories: [SuzzmeMemoryRecord] = []
    @State private var message: String?
    @State private var confirmClear = false
    @State private var memoryEnabled = false
    @State private var searchText = ""
    @State private var selectedType: SuzzmeMemoryType?
    @State private var isLoading = true
    @State private var showsConversation = false

    private var filteredMemories: [SuzzmeMemoryRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return memories.filter {
            (selectedType == nil || $0.type == selectedType)
                && (query.isEmpty || $0.name.localizedStandardContains(query) || $0.detail.localizedStandardContains(query))
        }
    }

    private var visibleCategories: [SuzzmeMemoryType] {
        SuzzmeMemoryType.allCases.filter { type in filteredMemories.contains { $0.type == type } }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                    SuzzmeScreenIntroduction(title: "The details that stay with you", message: "Useful details you choose to share, kept on this device.")
                    if !isLoading && !memories.isEmpty {
                        Text("\(memories.count) saved \(memories.count == 1 ? "detail" : "details")")
                            .font(.caption)
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                }
                .padding(.vertical, SuzzmeTheme.Spacing.xs)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if isLoading {
                Section {
                    ProgressView("Loading your memory…")
                        .font(.subheadline)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }
            } else if !memoryEnabled && message == nil {
                Section {
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                        Text("Personal Memory is off").font(.headline)
                        Text("Turn it on to carry useful details between conversations. You can inspect and forget them here.")
                            .font(.subheadline)
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Turn on Personal Memory") {
                        Task { await environment.setPersonalMemoryEnabled(true); await reload() }
                    }
                }
            } else if memoryEnabled && memories.isEmpty && message == nil {
                Section {
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                        Text("What would you like Suzzme to remember?").font(.headline)
                        Text("Tell Suzzme your main project or a preference, in your own words.")
                            .font(.subheadline)
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Tell Suzzme") { showsConversation = true }
                }
            } else if memoryEnabled && !memories.isEmpty {
                Section {
                    Picker("Category", selection: $selectedType) {
                        Text("All memories").tag(SuzzmeMemoryType?.none)
                        ForEach(SuzzmeMemoryType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(Optional(type))
                        }
                    }
                    .pickerStyle(.menu)
                }
                if filteredMemories.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No matching memories", systemImage: "magnifyingglass")
                        } description: {
                            Text("Try another search or choose a different category.")
                        } actions: {
                            Button("Show all memories") { searchText = ""; selectedType = nil }
                        }
                    }
                }
                ForEach(visibleCategories, id: \.self) { type in
                    Section(type.displayName) {
                        ForEach(filteredMemories.filter { $0.type == type }) { memory in
                            NavigationLink { MemoryDetailView(memory: memory, onForgotten: reload) } label: {
                                HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.medium) {
                                    Image(systemName: symbol(for: memory.type))
                                        .font(.title3)
                                        .foregroundStyle(SuzzmeTheme.textSecondary)
                                        .frame(width: SuzzmeTheme.Spacing.extraLarge)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                                        Text(memory.name).font(.headline)
                                        Text(memory.detail).font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(memory.provenance.humanDescription).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(.vertical, SuzzmeTheme.Spacing.xs)
                                .accessibilityElement(children: .combine)
                            }
                            .accessibilityHint("View this memory and where it came from")
                        }
                    }
                }
            }

            if let message {
                Section {
                    Label("Memory needs attention", systemImage: "exclamationmark.circle")
                        .font(.headline)
                    Text(message).font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { Task { await reload() } }
                }
            }
            if !isLoading {
                Section {
                    Toggle("Personal Memory", isOn: Binding(get: { memoryEnabled }, set: { value in
                        memoryEnabled = value
                        Task { await environment.setPersonalMemoryEnabled(value); await reload() }
                    }))
                    if !memories.isEmpty {
                        Button("Delete Suzzme Memory", role: .destructive) { confirmClear = true }
                    }
                } header: {
                    Text("Memory controls")
                } footer: {
                    Text("Memory stays on this device. It is separate from your current day and recent source updates.")
                        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .suzzmeReadableList()
        .navigationTitle("Personal Memory")
        .searchable(text: $searchText, prompt: "Search your memory")
        .task { await reload() }
        .refreshable { await reload() }
        .toolbar { Button("Remember something", systemImage: "plus") { showsConversation = true }.accessibilityLabel("Remember something with Suzzme") }
        .sheet(isPresented: $showsConversation, onDismiss: { Task { await reload() } }) {
            AskSuzzmeView(focusInput: true).frame(minWidth: 300, minHeight: 420)
        }
        .confirmationDialog("Delete all Suzzme Memory?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete All Memory", role: .destructive) { Task { await clear() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes only Suzzme’s personal memory. Calendar, Contacts, Reminders, and recent source information are not affected.")
        }
    }

    private func reload() async {
        defer { isLoading = false }
        memoryEnabled = await environment.personalMemoryEnabled()
        do {
            memories = try await environment.personalMemories()
            message = nil
        } catch { message = "Personal Memory couldn’t be loaded. Please try again." }
    }
    private func clear() async {
        do { try await environment.clearPersonalMemory(); await reload() }
        catch { message = "Personal Memory couldn’t be deleted. Please try again." }
    }
    private func symbol(for type: SuzzmeMemoryType) -> String {
        switch type {
        case .person: "person"
        case .project: "folder"
        case .commitment: "checkmark.seal"
        case .preference: "slider.horizontal.3"
        case .event: "calendar"
        case .place: "mappin"
        case .task: "checklist"
        case .organization: "building.2"
        case .topic: "text.book.closed"
        }
    }
}

private struct MemoryDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let memory: SuzzmeMemoryRecord
    let onForgotten: () async -> Void
    @State private var confirmsForget = false
    @State private var message: String?
    @State private var showsConversation = false

    private var correctionRequest: String? {
        switch memory.semanticSlot {
        case .mainProject: "Remember that my main project is now \(memory.name)"
        case .meetingTimePreference: "I actually prefer \(memory.name) meetings"
        case nil: nil
        }
    }

    var body: some View {
        List {
            Section {
                Text(memory.detail).font(.body).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Category", value: memory.type.displayName)
                if let expiresAt = memory.expiresAt {
                    LabeledContent("Remembered until", value: expiresAt.formatted(date: .abbreviated, time: .omitted))
                }
            } header: { Text("What Suzzme knows") }
            Section("Where it came from") {
                Label(memory.provenance.humanDescription, systemImage: "person.wave.2")
            }
            Section {
                Button(correctionRequest == nil ? "Talk about this memory" : "Correct with Suzzme") { showsConversation = true }
            } footer: {
                Text(correctionRequest == nil ? "To remove an incorrect detail, forget it below. Suzzme can update your main project and meeting preferences when you ask." : "Edit the request to say what has changed, then send it to Suzzme. Opening the conversation changes nothing.")
            }
            Section {
                Button("Forget This Memory", role: .destructive) { confirmsForget = true }
            } footer: {
                Text("Forgetting removes this detail and its memory relationships from Suzzme. It does not change Calendar, Contacts, Reminders, or recent source information.")
            }
            if let message { Section { Text(message).foregroundStyle(SuzzmeTheme.textSecondary) } }
        }
        .suzzmeReadableList()
        .navigationTitle(memory.name)
        .sheet(isPresented: $showsConversation, onDismiss: {
            Task { await onForgotten() }
            dismiss()
        }) {
            AskSuzzmeView(initialText: correctionRequest ?? "What do you remember about \(memory.name)?", focusInput: true)
                .frame(minWidth: 300, minHeight: 420)
        }
        .confirmationDialog("Forget “\(memory.name)” ?", isPresented: $confirmsForget, titleVisibility: .visible) {
            Button("Forget Memory", role: .destructive) { Task { await forget() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This cannot be undone.") }
    }
    private func forget() async {
        do {
            try await environment.deleteMemory(memory)
            await onForgotten()
            dismiss()
        } catch { message = "That memory couldn’t be forgotten. Please try again." }
    }
}

private extension SuzzmeMemoryType {

    var displayName: String {
        switch self {
        case .person: "People"
        case .project: "Projects"
        case .commitment: "Commitments"
        case .preference: "Preferences"
        case .event: "Events"
        case .place: "Places"
        case .task: "Tasks"
        case .organization: "Organizations"
        case .topic: "Topics"
        }
    }
}

private extension SuzzmeMemoryProvenance {
    var humanDescription: String {
        switch self {
        case .userExplicit: "You asked Suzzme to remember this"
        case .conversation: "Learned from a conversation with Suzzme"
        case .calendar: "Learned from Calendar context"
        case .reminders: "Learned from Reminders context"
        case .contacts: "Learned from Contacts context"
        }
    }
}
