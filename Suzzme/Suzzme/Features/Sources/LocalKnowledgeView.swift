import SwiftUI
import UniformTypeIdentifiers

struct LocalKnowledgeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var search = ""
    @State private var question = ""
    @State private var showsAdd = false
    @State private var showsImporter = false
    @State private var showsFolderImporter = false
    @State private var showsExporter = false
    @State private var export = KnowledgeMarkdownDocument(text: "")
    @State private var transferError: String?

    private var library: LocalKnowledgeController { environment.localKnowledge }
    private var filtered: [LocalKnowledgeNote] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? library.notes : library.notes.filter { ($0.title + " " + $0.text).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Form {
            Section {
                SuzzmeScreenIntroduction(title: "Knowledge, kept close",
                    message: "Choose text, Markdown, or a folder to understand on this device. Suzzme keeps useful source excerpts you can inspect, search, and remove.")
                ViewThatFits(in: .horizontal) {
                    HStack { addButton; importButton; importFolderButton }
                    VStack(alignment: .leading) { addButton; importButton; importFolderButton }
                }
                .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                .disabled(library.isWorking)
                Text("Uses Apple’s on-device model when available. Sensitive documents are not kept. Privacy checks are conservative filters, not a guarantee. Only selected excerpts and change fingerprints are saved; original files are unchanged.")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            if library.isWorking {
                Section {
                    Label(library.status ?? "Analyzing on this device…", systemImage: "hourglass")
                        .accessibilityIdentifier("suzzme-knowledge-working")
                    Button("Stop", role: .cancel) { library.cancel() }
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        .accessibilityIdentifier("suzzme-knowledge-stop")
                }
            } else if let status = library.status {
                Section { Text(status).font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary) }
            }
            if let error = library.error ?? transferError {
                Section {
                    Label(error, systemImage: "exclamationmark.circle")
                    Button("Dismiss") { library.dismissError(); transferError = nil }
                }
            }
            #if os(macOS)
            Section("Daily Summary") {
                InformationSourceControls(source: .localKnowledge, canEnable: !library.notes.isEmpty)
                Text("When enabled, only excerpts saved today can appear in the Mac Daily Summary. Suzzme does not watch the folder or rescan original files.")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            #endif
            Section("Saved excerpts") {
                if !library.isLoaded && library.error == nil {
                    ProgressView("Opening your library…")
                } else if library.notes.isEmpty {
                    Text("Your library is empty. Add a short note or choose a text file to begin.")
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                } else if filtered.isEmpty {
                    Text("No matching notes. Try another phrase.").foregroundStyle(SuzzmeTheme.textSecondary)
                } else {
                    ForEach(filtered) { note in
                        NavigationLink { LocalKnowledgeDetail(noteID: note.id) } label: {
                            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                                Text(note.title).font(.headline)
                                Text(note.excerpts.first ?? "").font(.subheadline).lineLimit(2)
                                    .foregroundStyle(SuzzmeTheme.textSecondary)
                                Text(note.analyzedAt, format: .dateTime.month().day().hour().minute()).font(.caption)
                                    .foregroundStyle(SuzzmeTheme.textSecondary)
                            }
                            .padding(.vertical, SuzzmeTheme.Spacing.xs)
                        }
                    }
                }
            }
            Section {
                TextField("Ask a question using a name or phrase from a note", text: $question, axis: .vertical)
                    .accessibilityLabel("Question about your local library")
                    .accessibilityIdentifier("suzzme-knowledge-question")
                    .onSubmit { ask() }
                Button("Ask Your Library", systemImage: "text.magnifyingglass", action: ask)
                    .disabled(library.isWorking || library.notes.isEmpty || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || question.count > 1_000)
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                    .accessibilityIdentifier("suzzme-knowledge-ask")
                if let answer = library.answer {
                    Text(answer.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Label(answer.usedModel ? "Generated on this device · Check the sources" : "Local library result",
                        systemImage: "desktopcomputer").font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    ForEach(Array(answer.sources.enumerated()), id: \.offset) { _, note in
                        NavigationLink { LocalKnowledgeDetail(noteID: note.id) } label: {
                            Label(note.title, systemImage: "doc.text")
                        }
                    }
                }
            } header: { Text("Ask about your notes") } footer: {
                Text("Answers use matching saved excerpts, not live source verification. Each question stands on its own. This read-only feature cannot change calendars, send messages, or save Personal Memory.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Button("Export Markdown", systemImage: "square.and.arrow.up") {
                    export = .init(text: LocalKnowledgeEngine.markdown(library.notes))
                    showsExporter = true
                }
                .disabled(library.notes.isEmpty || library.isWorking)
                .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            } footer: {
                Text("Choose where to save the export. Sharing or syncing that file follows the destination you choose.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .suzzmeSettingsForm()
        .navigationTitle("Local Knowledge")
        .searchable(text: $search, prompt: "Search saved excerpts")
        .task { await library.load(); await environment.inspectInformation() }
        .onChange(of: library.notes) { _, _ in
            #if os(macOS)
            Task { await environment.refreshInformation(force: true, source: .localKnowledge) }
            #endif
        }
        .onDisappear { library.cancel() }
        .sheet(isPresented: $showsAdd) { AddKnowledgeTextView(library: library) }
        .fileImporter(isPresented: $showsImporter,
            allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): library.importFiles(urls)
                case .failure: transferError = "The selected files couldn’t be opened. Try selecting them again."
                }
            }
        .fileImporter(isPresented: $showsFolderImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let folder = urls.first { library.importFolder(folder) }
                else { transferError = LocalKnowledgeError.unsupportedFolder.localizedDescription }
            case .failure: transferError = "The selected folder couldn’t be opened. Nothing was imported."
            }
        }
        .fileExporter(isPresented: $showsExporter, document: export, contentType: .plainText, defaultFilename: "Suzzme Local Knowledge.md") { result in
            if case .failure = result { transferError = "The Markdown export couldn’t be saved. Choose another location and try again." }
        }
    }
    private func ask() {
        guard !library.isWorking, !library.notes.isEmpty, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, question.count <= 1_000 else { return }
        library.ask(question)
    }
    private var addButton: some View {
        Button("Add Text", systemImage: "plus") { showsAdd = true }
            .buttonStyle(.borderless)
            .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            .accessibilityIdentifier("suzzme-knowledge-add")
    }
    private var importButton: some View {
        Button("Import Files", systemImage: "doc.badge.plus") { showsImporter = true }
            .buttonStyle(.borderless)
            .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            .accessibilityIdentifier("suzzme-knowledge-import")
    }
    private var importFolderButton: some View {
        Button("Import Folder", systemImage: "folder.badge.plus") { showsFolderImporter = true }
            .buttonStyle(.borderless)
            .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            .accessibilityIdentifier("suzzme-knowledge-import-folder")
    }
}

private struct AddKnowledgeTextView: View {
    let library: LocalKnowledgeController
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Document") {
                    TextField("Title", text: $title).accessibilityIdentifier("suzzme-knowledge-title")
                    TextField("Paste text to analyze", text: $text, axis: .vertical)
                        .lineLimit(8...16).accessibilityIdentifier("suzzme-knowledge-text")
                    Text("\(text.count.formatted()) of 6,000 characters").font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                }
                Section { Text("Only useful, exact excerpts are retained. Model analysis happens locally and may take a moment.") }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Analyze") { library.add([.init(title: title, text: text)]); dismiss() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 100 || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > LocalKnowledgeLimits.characters || library.isWorking)
                        .accessibilityIdentifier("suzzme-knowledge-analyze")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: SuzzmeTheme.Layout.assistantMinimumWidth,
            idealWidth: SuzzmeTheme.Layout.readingWidth, minHeight: SuzzmeTheme.Layout.windowMinHeight)
        #endif
    }
}

private struct LocalKnowledgeDetail: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsRemoval = false
    let noteID: UUID
    private var note: LocalKnowledgeNote? { environment.localKnowledge.notes.first { $0.id == noteID } }
    var body: some View {
        Form {
            if let note {
                Section {
                    Text(note.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                    Text("Analyzed \(note.analyzedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    Text("Exact source excerpts selected by the on-device model. They reflect the imported document, which may be outdated.")
                        .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                }
                Section("Source excerpts") {
                    ForEach(Array(note.excerpts.enumerated()), id: \.offset) { _, excerpt in
                        Text(excerpt).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section {
                    Button("Remove from Library…", role: .destructive) { confirmsRemoval = true }
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
            } else { Text("This note is no longer in your library.") }
        }
        .suzzmeSettingsForm().navigationTitle("Knowledge Note")
        .confirmationDialog("Remove this note?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove from Library", role: .destructive) {
                if let note { Task { await environment.localKnowledge.remove(note); if self.note == nil { dismiss() } } }
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This removes its saved excerpts and change fingerprint from Suzzme. Original files and exports are unchanged.") }
    }
}

private struct KnowledgeMarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
