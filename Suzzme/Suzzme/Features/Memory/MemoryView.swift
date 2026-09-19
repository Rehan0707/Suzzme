import SwiftUI

struct MemoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var memories: [SuzzmeMemoryRecord] = []
    @State private var message: String?
    @State private var confirmClear = false
    @State private var memoryEnabled = false
    var body: some View {
        SuzzmePage {
            SuzzmeCard {
                Toggle("Personal Memory", isOn: Binding(get: { memoryEnabled }, set: { value in memoryEnabled = value; Task { await environment.setPersonalMemoryEnabled(value) } }))
                Text("Suzzme remembers useful details you choose to share so conversations can stay personal and continuous. Memory stays on this device.").font(.subheadline).foregroundStyle(.secondary)
            }
            if memories.isEmpty {
                SuzzmeEmptyState(symbol: "square.stack.3d.up", title: "Less to hold in your head.", message: "Suzzme hasn’t saved any personal memories yet.")
            } else {
                SuzzmeSectionHeader(title: "Personal memory")
                ForEach(memories, id: \.id) { memory in
                    SuzzmeCard {
                        Label(memory.type.rawValue.capitalized, systemImage: symbol(for: memory.type)).font(.caption).foregroundStyle(SuzzmeTheme.accent)
                        Text(memory.name).font(.headline)
                        Text(memory.detail).foregroundStyle(.secondary)
                        Text("From \(memory.provenance == .userExplicit ? "your conversation" : memory.provenance.rawValue)").font(.caption).foregroundStyle(.secondary)
                        Button("Delete", role: .destructive) { Task { await delete(memory) } }.buttonStyle(.bordered)
                    }
                }
                Button("Delete Suzzme Memory", role: .destructive) { confirmClear = true }.buttonStyle(.bordered)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle("Memory")
        .task { await reload() }
        .confirmationDialog("Delete all Suzzme Memory?", isPresented: $confirmClear, titleVisibility: .visible) { Button("Delete All Memory", role: .destructive) { Task { await clear() } } } message: { Text("This deletes only Suzzme’s personal memory. Calendar, Contacts, and Reminders are not affected.") }
    }
    private func reload() async { do { memories = try await environment.personalMemories(); memoryEnabled = await environment.personalMemoryEnabled() } catch { message = error.localizedDescription } }
    private func delete(_ memory: SuzzmeMemoryRecord) async { do { try await environment.deleteMemory(memory); await reload() } catch { message = error.localizedDescription } }
    private func clear() async { do { try await environment.clearPersonalMemory(); await reload() } catch { message = error.localizedDescription } }
    private func symbol(for type: SuzzmeMemoryType) -> String { switch type { case .person: "person"; case .project: "folder"; case .preference: "slider.horizontal.3"; default: "circle" } }
}
