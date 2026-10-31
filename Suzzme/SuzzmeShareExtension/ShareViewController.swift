import SwiftUI
import Observation
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor @Observable
private final class SharePageModel {
    var address: String?
    var message: String?
    var isLoading = true
    private var context: NSExtensionContext?
    private var loaded = false
    private var inputGeneration = UUID()
    @ObservationIgnored private var readTimeout: Task<Void, Never>?
    deinit { readTimeout?.cancel() }
    let isConfigured = (try? SharedWebInbox()) != nil

    func load(_ context: NSExtensionContext?) {
        guard !loaded else { return }; loaded = true; self.context = context
        let items = context?.inputItems as? [NSExtensionItem] ?? []
        guard items.count <= 8 else { fail(SharedWebInboxError.unsupported); return }
        let providers = items.flatMap { Array(($0.attachments ?? []).prefix(9)) }
        // Never request plain text, images, files, HTML, DOM, or account data.
        let urls = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }
        guard urls.count == 1, providers.count <= 8 else {
            fail(SharedWebInboxError.unsupported); return
        }
        let generation = inputGeneration
        readTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, self.inputGeneration == generation, self.isLoading else { return }
            self.fail(SharedWebInboxError.timeout)
        }
        urls[0].loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] value, error in
            let raw = error == nil ? ((value as? URL)?.absoluteString ?? value as? String) : nil
            Task { @MainActor [weak self] in
                guard let self, self.inputGeneration == generation, self.isLoading else { return }
                guard let raw, let canonical = try? SharedWebInbox.canonicalURL(raw) else {
                    self.fail(SharedWebInboxError.unsupported); return
                }
                self.readTimeout?.cancel(); self.readTimeout = nil
                self.address = canonical.absoluteString; self.isLoading = false
            }
        }
    }
    func send() {
        guard let address else { return }
        do {
            _ = try SharedWebInbox().enqueue(address)
            inputGeneration = UUID(); readTimeout?.cancel(); self.address = nil
            context?.completeRequest(returningItems: nil, completionHandler: nil)
        } catch { fail(error) }
    }
    func cancel() {
        inputGeneration = UUID(); readTimeout?.cancel(); address = nil; isLoading = false
        context?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
    private func fail(_ error: Error) {
        readTimeout?.cancel(); readTimeout = nil; isLoading = false
        message = (error as? SharedWebInboxError)?.localizedDescription ?? SharedWebInboxError.storage.localizedDescription
    }
}

private struct SharePageView: View {
    let model: SharePageModel
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SuzzmeMark().frame(width: 48, height: 48)
                    Text("Share a page with Suzme").font(.headline)
                    Text("Only this URL is queued on this device. Page contents and account data are not read. Query strings and fragments are removed.")
                }
                Section("Review the URL") {
                    if model.isLoading { ProgressView("Reading the URL you selected…") }
                    if let address = model.address { Text(address).textSelection(.enabled) }
                    if let message = model.message { Text(message).foregroundStyle(.secondary) }
                    if !model.isConfigured { Text(SharedWebInboxError.unavailable.localizedDescription).foregroundStyle(.secondary) }
                }
                Section {
                    Text("After sharing, open Suzme → Sources → Shared webpages. URLs stay available for up to ten minutes; expired queue files are removed when the app or Share extension next checks the queue. Nothing is automatically added to memory or fetched from the web.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Send URL to Suzme") { model.send() }
                        .disabled(model.address == nil || !model.isConfigured || model.isLoading)
                        .frame(minHeight: 44)
                }
            }
            .navigationTitle("Suzme")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { model.cancel() }.keyboardShortcut(.cancelAction)
                }
            }
        }
    }
}

#if os(iOS)
final class ShareViewController: UIViewController {
    private let model = SharePageModel()
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: SharePageView(model: model))
        addChild(host); host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self); model.load(extensionContext)
    }
}
#else
final class ShareViewController: NSViewController {
    private let model = SharePageModel()
    override func loadView() { view = NSHostingView(rootView: SharePageView(model: model)) }
    override func viewDidLoad() { super.viewDidLoad(); preferredContentSize = NSSize(width: 440, height: 520); model.load(extensionContext) }
}
#endif
