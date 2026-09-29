import SwiftUI

struct MemoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var memories: [SuzzmeMemoryRecord] = []
    @State private var message: String?
    @State private var confirmClear = false
    @State private var memoryEnabled = false

    var body: some View {
        SuzzmePage {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                Toggle("Personal Memory", isOn: Binding(
                    get: { memoryEnabled },
                    set: { value in memoryEnabled = value; Task { await environment.setPersonalMemoryEnabled(value) } }
                ))
                .font(.headline)
                Text("Suzzme remembers useful details you choose to share. Memory stays on this device and remains under your control.")
                    .font(.subheadline)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            }

            if !memoryEnabled {
                SuzzmeEmptyState(symbol: "memorychip", title: "Personal Memory is off", message: "Turn it on when you want Suzzme to remember details between conversations.")
            } else if memories.isEmpty {
                SuzzmeEmptyState(symbol: "square.stack.3d.up", title: "Nothing saved yet", message: "Details you explicitly ask Suzzme to remember will appear here.")
            } else {
                ForEach(SuzzmeMemoryType.allCases.filter { type in memories.contains { $0.type == type } }, id: \.self) { type in
                SuzzmeSectionHeader(title: type.displayName)
                ForEach(memories.filter { $0.type == type }, id: \.id) { memory in
                    NavigationLink { MemoryDetailView(memory: memory, onForgotten: reload) } label: {
                        HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.medium) {
                            Image(systemName: symbol(for: memory.type))
                                .foregroundStyle(SuzzmeTheme.textSecondary)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                                Text(memory.name).font(.headline)
                                Text(memory.detail).font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(SuzzmeTheme.textTertiary)
                        }
                        .padding(.vertical, SuzzmeTheme.Spacing.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                }

                Button("Delete Suzzme Memory", role: .destructive) { confirmClear = true }
                    .buttonStyle(.bordered)
            }

            if let message { Text(message).font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary) }
        }
        .navigationTitle("Memory")
        .task { await reload() }
        .confirmationDialog("Delete all Suzzme Memory?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete All Memory", role: .destructive) { Task { await clear() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes only Suzzme’s personal memory. Calendar, Contacts, Reminders, and recent source information are not affected.")
        }
    }

    private func reload() async {
        do {
            memories = try await environment.personalMemories()
            memoryEnabled = await environment.personalMemoryEnabled()
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

    var body: some View {
        List {
            Section("What Suzzme knows") {
                LabeledContent("Category", value: memory.type.displayName)
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                    Text(memory.name).font(.headline)
                    Text(memory.detail).foregroundStyle(SuzzmeTheme.textSecondary)
                }
                if let expiresAt = memory.expiresAt {
                    LabeledContent("Remembered until", value: expiresAt.formatted(date: .abbreviated, time: .omitted))
                }
            }
            Section("Where it came from") {
                Label(memory.provenance.humanDescription, systemImage: "person.wave.2")
            }
            Section {
                Button("Forget This Memory", role: .destructive) { confirmsForget = true }
            } footer: {
                Text("Forgetting removes this detail and its memory relationships from Suzzme. It does not change Calendar, Contacts, Reminders, or recent source information.")
            }
            if let message { Section { Text(message).foregroundStyle(SuzzmeTheme.textSecondary) } }
        }
        .navigationTitle(memory.name)
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
