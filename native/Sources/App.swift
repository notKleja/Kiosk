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
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Kiosk") { showAbout() }
            }
        }
    }

    private func showAbout() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Kiosk",
            .applicationVersion: version,
            .version: "build \(build)",
            .credits: NSAttributedString(
                string: "App icons from Google Play and the App Store.\n"
                    + "github.com/notKleja/Kiosk",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]),
        ])
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
    var upscale = false {
        didSet { UserDefaults.standard.set(upscale, forKey: "upscale") }
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
        upscale = defaults.bool(forKey: "upscale")
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

    struct Icon {
        let data: Data
        let pixels: Int
    }

    @ObservationIgnored private lazy var clipboardTempDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func png(for app: PlayApp) async throws -> Icon {
        let data = try await store.iconData(app, size: size)
        return try await IconRenderer.render(data, size: size, upscale: upscale)
    }

    @discardableResult
    func save(_ app: PlayApp) async throws -> URL {
        let icon = try await png(for: app)
        try FileManager.default.createDirectory(
            at: saveDirectory, withIntermediateDirectories: true)
        let base = PlayApp.sanitizedFileName(app.pkg)
        let url = uniqueURL(in: saveDirectory, stem: "\(base)_\(icon.pixels)")
        try icon.data.write(to: url, options: .atomic)
        return url
    }

    private func uniqueURL(in directory: URL, stem: String) -> URL {
        var candidate = directory.appending(path: "\(stem).png")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(stem) \(suffix).png")
            suffix += 1
        }
        return candidate
    }

    @discardableResult
    func copy(_ app: PlayApp) async throws -> Int {
        let icon = try await png(for: app)
        let png = icon.data
        let name = PlayApp.sanitizedFileName("\(app.name) \(icon.pixels)px")
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setString(app.name, forType: .string)

        var objects: [NSPasteboardWriting] = [item]
        if let image = NSImage(data: png) { objects.append(image) }
        let temp = clipboardTempDirectory.appending(path: "\(name).png")
        if (try? png.write(to: temp)) != nil { objects.insert(temp as NSURL, at: 0) }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(objects)
        return icon.pixels
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

enum IconError: Error, LocalizedError {
    case notAnImage

    var errorDescription: String? {
        switch self {
        case .notAnImage:
            return "The downloaded data isn't a valid image."
        }
    }
}

nonisolated enum IconRenderer {
    static func render(_ data: Data, size: Int, upscale: Bool) async throws -> IconModel.Icon {
        guard let image = NSBitmapImageRep(data: data) else {
            throw IconError.notAnImage
        }
        if upscale, image.pixelsWide < size, let scaled = resize(image, to: size) {
            return IconModel.Icon(data: scaled, pixels: size)
        }
        guard let png = image.representation(using: .png, properties: [:]) else {
            throw IconError.notAnImage
        }
        return IconModel.Icon(data: png, pixels: image.pixelsWide)
    }

    private static func resize(_ image: NSBitmapImageRep, to size: Int) -> Data? {
        guard let target = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        target.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        return target.representation(using: .png, properties: [:])
    }
}
