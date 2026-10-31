import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SharedAppContextView: View {
    var initialSource: SharedAppSource = .other
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        SharedAppWorkspace(controller: environment.makeSharedAppWorkspace(), source: initialSource)
    }
}

private struct SharedAppWorkspace: View {
    @State private var controller: SharedAppContextController
    @State private var source: SharedAppSource
    @State private var task = SharedAppTask.question
    @State private var question = ""
    @State private var showsImporter = false
    @State private var copied = false

    init(controller: SharedAppContextController, source: SharedAppSource) {
        _controller = State(initialValue: controller); _source = State(initialValue: source)
    }

    private var canAsk: Bool {
        !controller.isWorking && !controller.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && controller.text.count <= SharedAppSnapshot.maximumCharacters && question.count <= 700
            && (task != .question || !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        Form {
            Section {
                Label("Selected content, understood locally", systemImage: "app.connected.to.app.below.fill")
                    .font(.headline)
                Text("Copy the relevant conversation, post, or issue from an app and paste it below, or choose a screenshot. Only the content you share is used.")
                    .foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Shared source") {
                Picker("From app", selection: $source) {
                    ForEach(SharedAppSource.allCases) { Text($0.title).tag($0) }
                }.disabled(controller.isWorking).accessibilityIdentifier("suzzme-shared-app-source")
                Button("Choose Screenshot…", systemImage: "photo") { showsImporter = true }
                    .disabled(controller.isWorking).frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                    .accessibilityIdentifier("suzzme-shared-app-screenshot")
                TextField("Paste or review shared text", text: Binding(get: { controller.text }, set: { controller.edit($0) }), axis: .vertical)
                    .lineLimit(5...12).disabled(controller.isWorking)
                    .accessibilityLabel("Shared app text").accessibilityIdentifier("suzzme-shared-app-text")
                Text("\(controller.text.count.formatted()) of 4,500 characters")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                if controller.fromScreenshot {
                    Label("Recognized from your screenshot. Review and correct the text before asking.", systemImage: "text.viewfinder")
                        .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                }
                Text("This is a user-shared excerpt, not a connected account or live inbox. App identity is the label you choose.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            Section("Ask Suzzme") {
                Picker("Help with", selection: $task) {
                    ForEach(SharedAppTask.allCases) { Text($0.title).tag($0) }
                }.disabled(controller.isWorking).accessibilityIdentifier("suzzme-shared-app-task")
                TextField(task == .question ? "Your question" : "Optional instructions", text: $question, axis: .vertical)
                    .lineLimit(2...4).disabled(controller.isWorking).onSubmit(ask)
                    .accessibilityIdentifier("suzzme-shared-app-question")
                Text("\(question.count) of 700 characters").font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                if controller.isWorking {
                    ProgressView(controller.status ?? "Working on this device…")
                    Button("Stop", role: .cancel) { controller.cancel() }
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        .accessibilityIdentifier("suzzme-shared-app-stop")
                } else {
                    Button(task == .reply ? "Create Draft" : task == .summary ? "Summarize Excerpt" : "Ask About Excerpt", action: ask)
                        .disabled(!canAsk).keyboardShortcut(.return, modifiers: .command)
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        .accessibilityIdentifier("suzzme-shared-app-ask")
                }
                if let error = controller.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                } else if let status = controller.status, !controller.isWorking {
                    Text(status).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            if let answer = controller.answer {
                Section(answer.task == .reply ? "Draft · review before using" : "Answer from shared content") {
                    Text(answer.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("suzzme-shared-app-answer")
                    Label("On-device answer · \(answer.source.source.title) excerpt", systemImage: "checkmark.shield")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    Text("Shared \(answer.source.sharedAt.formatted(date: .abbreviated, time: .shortened)). Review against the original app; excerpts may be incomplete or outdated.")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    DisclosureGroup("View source used") {
                        Text(answer.source.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }.accessibilityIdentifier("suzzme-shared-app-evidence")
                    Button(copied ? "Copied" : "Copy \(answer.task == .reply ? "Draft" : "Answer")", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        #if os(macOS)
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(answer.text, forType: .string)
                        #else
                        UIPasteboard.general.string = answer.text
                        #endif
                        copied = true
                    }.frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        .accessibilityIdentifier("suzzme-shared-app-copy")
                }
            }
            Section {
                Button("Clear Shared Content") { controller.clear(); question = ""; copied = false }
                    .disabled(controller.isWorking || controller.text.isEmpty)
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                Text("Nothing is sent back to the source app. Shared content stays in this workspace until you clear it or leave. It is not saved to Memory or Local Knowledge.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Shared App Context")
        .onChange(of: source) { _, _ in controller.invalidateAnswer(); copied = false }
        .onChange(of: task) { _, _ in controller.invalidateAnswer(); copied = false }
        .onChange(of: question) { _, _ in controller.invalidateAnswer(); copied = false }
        .onChange(of: controller.text) { _, _ in copied = false }
        .onDisappear { controller.clear(); question = "" }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.png, .jpeg]) { result in
            switch result {
            case .success(let url): controller.readScreenshot(url)
            case .failure: controller.showImportError()
            }
        }
    }
    private func ask() {
        guard canAsk else { return }
        copied = false; controller.ask(source: source, task: task, question: question)
    }
}
