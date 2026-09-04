import Foundation

let version = "1.1.0"

struct Options {
    var store: StoreSource = .play
    var country = "us"
    var limit = 20
    var size = 512
    var upscale = false
    var json = false
    var pkg: String?
    var output = FileManager.default.currentDirectoryPath
}

func usage() -> String {
    """
    kiosk \(version) — grab app icons from Google Play and the App Store

    USAGE
      kiosk search <query> [options]
      kiosk get <query> [options]
      kiosk --help | --version

    OPTIONS
      --store <play|appstore>   store to search (default play)
      --country <cc>            storefront, e.g. us, sa (default us)
      --limit <n>               results for search (default 20)
      --size <px>               icon size for get: 128, 256, 512, 1024 (default 512)
      --pkg <id>                with get, pick this exact bundle id from the results
      --out <dir>               directory to write into (default current directory)
      --upscale                 upscale when the store's icon is smaller than --size
      --json                    machine-readable output

    EXAMPLES
      kiosk search spotify
      kiosk get telegram --store appstore --size 1024 --out ~/Icons
      kiosk get "" --pkg com.spotify.music --size 512
    """
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("kiosk: \(message)\n".utf8))
    exit(1)
}

func parse(_ arguments: [String]) -> (command: String, query: String, options: Options) {
    var args = arguments
    guard !args.isEmpty else { print(usage()); exit(0) }

    let command = args.removeFirst()
    if command == "--help" || command == "-h" { print(usage()); exit(0) }
    if command == "--version" || command == "-v" { print(version); exit(0) }
    guard command == "search" || command == "get" else { fail("unknown command '\(command)'") }

    var options = Options()
    var query = ""

    while !args.isEmpty {
        let arg = args.removeFirst()
        func value(_ name: String) -> String {
            guard !args.isEmpty else { fail("\(name) needs a value") }
            return args.removeFirst()
        }
        switch arg {
        case "--store":
            let raw = value("--store").lowercased()
            switch raw {
            case "play", "google", "googleplay": options.store = .play
            case "appstore", "apple", "ios": options.store = .appStore
            default: fail("unknown store '\(raw)'")
            }
        case "--country": options.country = value("--country").lowercased()
        case "--limit":
            guard let n = Int(value("--limit")), n > 0, n <= 50 else { fail("--limit must be 1-50") }
            options.limit = n
        case "--size":
            guard let n = Int(value("--size")), n >= 16, n <= 4096 else { fail("--size must be 16-4096") }
            options.size = n
        case "--pkg": options.pkg = value("--pkg")
        case "--out": options.output = (value("--out") as NSString).expandingTildeInPath
        case "--upscale": options.upscale = true
        case "--json": options.json = true
        case "--help", "-h": print(usage()); exit(0)
        default:
            if arg.hasPrefix("-") { fail("unknown option '\(arg)'") }
            query = query.isEmpty ? arg : "\(query) \(arg)"
        }
    }

    if query.isEmpty, options.pkg == nil { fail("missing search query") }
    return (command, query.isEmpty ? (options.pkg ?? "") : query, options)
}

func printResults(_ apps: [PlayApp], json: Bool) {
    if json {
        let rows = apps.map { app -> [String: String] in
            ["pkg": app.pkg, "name": app.name, "developer": app.developer,
             "rating": app.rating, "icon": app.icon, "store": app.source.rawValue]
        }
        let data = try? JSONSerialization.data(
            withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data ?? Data("[]".utf8), as: UTF8.self))
        return
    }
    guard !apps.isEmpty else { print("no results"); return }
    let width = apps.map(\.pkg.count).max() ?? 0
    for app in apps {
        let pad = String(repeating: " ", count: width - app.pkg.count)
        let rating = app.rating.isEmpty ? "    " : "\(app.rating)★"
        print("\(app.pkg)\(pad)  \(rating)  \(app.name)")
    }
}

let (command, query, options) = parse(Array(CommandLine.arguments.dropFirst()))
let store = PlayStore()

do {
    let apps = try await store.search(
        query, source: options.store, country: options.country, limit: options.limit)

    if command == "search" {
        printResults(apps, json: options.json)
        exit(apps.isEmpty ? 1 : 0)
    }

    let picked: PlayApp?
    if let pkg = options.pkg {
        picked = apps.first { $0.pkg == pkg }
    } else {
        picked = apps.first
    }
    guard let app = picked else { fail("no matching app") }

    let data = try await store.iconData(app, size: options.size)
    let icon = try await IconRenderer.render(data, size: options.size, upscale: options.upscale)

    let directory = URL(filePath: options.output)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let stem = "\(PlayApp.sanitizedFileName(app.pkg))_\(icon.pixels)"
    var url = directory.appending(path: "\(stem).png")
    var suffix = 2
    while FileManager.default.fileExists(atPath: url.path) {
        url = directory.appending(path: "\(stem) \(suffix).png")
        suffix += 1
    }
    try icon.data.write(to: url, options: .atomic)

    if options.json {
        let row: [String: Any] = [
            "pkg": app.pkg, "name": app.name, "pixels": icon.pixels, "path": url.path,
        ]
        let out = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        print(String(decoding: out, as: UTF8.self))
    } else {
        let note = icon.pixels < options.size && !options.upscale
            ? "  (store max is \(icon.pixels)px)" : ""
        print("\(url.path)\(note)")
    }
} catch {
    fail(error.localizedDescription)
}
