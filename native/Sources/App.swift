import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct KioskApp: App {
    var body: some Scene {
        WindowGroup("Kiosk") {
            ContentView()
                .frame(minWidth: 420, idealWidth: 460, minHeight: 440, idealHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
@Observable
final class IconModel {
    var query = "" { didSet { scheduleSearch() } }
    var apps: [PlayApp] = []
    var loading = false
    var error: String?
    var size = 512 { didSet { UserDefaults.standard.set(size, forKey: "size") } }
    var source: StoreSource = .play {
        didSet {
            UserDefaults.standard.set(source.rawValue, forKey: "source")
            runSearch()
        }
    }
    var country = "us" {
        didSet {
            UserDefaults.standard.set(country, forKey: "country")
            runSearch()
        }
    }
    var saveDirectory: URL {
        didSet { UserDefaults.standard.set(saveDirectory.path, forKey: "saveDir") }
    }

    private let store = PlayStore()
    private var task: Task<Void, Never>?
    private var generation = 0

    init() {
        let defaults = UserDefaults.standard
        size = defaults.object(forKey: "size") as? Int ?? 512
        country = defaults.string(forKey: "country") ?? "us"
        source = defaults.string(forKey: "source").flatMap(StoreSource.init) ?? .play
        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Downloads/play-icons")
        saveDirectory = defaults.string(forKey: "saveDir").map { URL(filePath: $0) } ?? fallback
    }

    private func scheduleSearch() {
        task?.cancel()
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            apps = []
            error = nil
            loading = false
            return
        }
        loading = true
        generation += 1
        let current = generation
        task = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await load(text, generation: current)
        }
    }

    func runSearch() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { return }
        generation += 1
        let current = generation
        loading = true
        task?.cancel()
        task = Task { await load(text, generation: current) }
    }

    private func load(_ text: String, generation current: Int) async {
        do {
            let results = try await store.search(text, source: source, country: country)
            guard current == generation else { return }
            apps = results
            error = nil
        } catch {
            guard current == generation else { return }
            self.error = error.localizedDescription
        }
        loading = false
    }

    func png(for app: PlayApp) async throws -> Data {
        let data = try await store.iconData(app, size: size)
        guard let image = NSBitmapImageRep(data: data),
              let png = image.representation(using: .png, properties: [:])
        else { return data }
        return png
    }

    @discardableResult
    func save(_ app: PlayApp) async throws -> URL {
        let png = try await png(for: app)
        try FileManager.default.createDirectory(
            at: saveDirectory, withIntermediateDirectories: true)
        let url = saveDirectory.appending(path: "\(app.pkg)_\(size).png")
        try png.write(to: url)
        return url
    }

    func copy(_ app: PlayApp) async throws {
        let png = try await png(for: app)
        let name = "\(app.name) \(size)px".replacingOccurrences(of: "/", with: "-")
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setString(app.name, forType: .string)

        var objects: [NSPasteboardWriting] = [item]
        if let image = NSImage(data: png) { objects.append(image) }
        let temp = FileManager.default.temporaryDirectory.appending(path: "\(name).png")
        if (try? png.write(to: temp)) != nil { objects.insert(temp as NSURL, at: 0) }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(objects)
    }

    func pickSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save icons here"
        if panel.runModal() == .OK, let url = panel.url { saveDirectory = url }
    }
}
