import Foundation

let version = "1.2.0"

struct Options {
    var store: StoreSource = .play
    var country = "us"
    var limit = 20
    var size = 512
    var upscale = false
    var json = false
    var all = false
    var delay = 250
    var packages: [String] = []
    var output = FileManager.default.currentDirectoryPath
}

func usage() -> String {
    """
    kiosk \(version) — grab app icons from Google Play and the App Store

    USAGE
      kiosk search <query> [options]
      kiosk get <query> [<query> …] [options]
      kiosk --help | --version

    OPTIONS
      --store <play|appstore>   store to search (default play)
      --country <cc>            storefront, e.g. us, sa (default us)
      --limit <n>               results per search (default 20)
      --size <px>               icon size for get: 128, 256, 512, 1024 (default 512)
      --pkg <id>                download this exact bundle id; repeatable
      --all                     download every result of each query, not just the first
      --delay <ms>              pause between downloads (default 250, 0 to disable)
      --out <dir>               directory to write into (default current directory)
      --upscale                 upscale when the store's icon is smaller than --size
      --json                    machine-readable output

    EXAMPLES
      kiosk search spotify
      kiosk get telegram --store appstore --size 1024 --out ~/Icons
      kiosk get spotify whatsapp notion --size 512 --out ~/Icons
      kiosk get "photo editor" --all --limit 10 --delay 500 --out ~/Icons
      kiosk get --pkg com.spotify.music --pkg com.snapchat.android --size 512
    """
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("kiosk: \(message)\n".utf8))
    exit(1)
}

func note(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}

func parse(_ arguments: [String]) -> (command: String, queries: [String], options: Options) {
    var args = arguments
    guard !args.isEmpty else { print(usage()); exit(0) }

    let command = args.removeFirst()
    if command == "--help" || command == "-h" { print(usage()); exit(0) }
    if command == "--version" || command == "-v" { print(version); exit(0) }
    guard command == "search" || command == "get" else { fail("unknown command '\(command)'") }

    var options = Options()
    var queries: [String] = []

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
        case "--delay":
            guard let n = Int(value("--delay")), n >= 0, n <= 60_000 else { fail("--delay must be 0-60000") }
            options.delay = n
        case "--pkg": options.packages.append(value("--pkg"))
        case "--all": options.all = true
        case "--out": options.output = (value("--out") as NSString).expandingTildeInPath
        case "--upscale": options.upscale = true
        case "--json": options.json = true
        case "--help", "-h": print(usage()); exit(0)
        default:
            if arg.hasPrefix("-") { fail("unknown option '\(arg)'") }
            queries.append(arg)
        }
    }

    if queries.isEmpty, options.packages.isEmpty { fail("missing search query") }
    if command == "search", queries.isEmpty { fail("missing search query") }
    return (command, queries, options)
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

func uniqueURL(in directory: URL, stem: String) -> URL {
    var candidate = directory.appending(path: "\(stem).png")
    var suffix = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
        candidate = directory.appending(path: "\(stem) \(suffix).png")
        suffix += 1
    }
    return candidate
}

func progress(_ done: Int, _ total: Int, _ text: String) {
    let width = 18
    let filled = total == 0 ? 0 : Int(Double(width) * Double(done) / Double(total))
    let bar = String(repeating: "█", count: filled)
        + String(repeating: "░", count: width - filled)
    let line = "\r\u{1B}[K[\(done)/\(total)] \(bar) \(text)"
    FileHandle.standardError.write(Data(line.utf8))
}

let (command, queries, options) = parse(Array(CommandLine.arguments.dropFirst()))
let store = PlayStore()
let interactive = isatty(FileHandle.standardError.fileDescriptor) == 1

do {
    if command == "search" {
        var found: [PlayApp] = []
        for query in queries {
            found += try await store.search(
                query, source: options.store, country: options.country, limit: options.limit)
        }
        printResults(found, json: options.json)
        exit(found.isEmpty ? 1 : 0)
    }

    var targets: [PlayApp] = []
    var seen = Set<String>()

    for query in queries {
        let apps = try await store.search(
            query, source: options.store, country: options.country, limit: options.limit)
        guard !apps.isEmpty else {
            note("kiosk: no results for '\(query)'")
            continue
        }
        for app in (options.all ? apps : [apps[0]]) where seen.insert(app.id).inserted {
            targets.append(app)
        }
    }

    for pkg in options.packages {
        if targets.contains(where: { $0.pkg == pkg }) { continue }
        let apps = try await store.search(
            pkg, source: options.store, country: options.country, limit: options.limit)
        guard let match = apps.first(where: { $0.pkg == pkg }) else {
            note("kiosk: no app with bundle id '\(pkg)'")
            continue
        }
        if seen.insert(match.id).inserted { targets.append(match) }
    }

    guard !targets.isEmpty else { fail("nothing to download") }

    let directory = URL(filePath: options.output)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var written: [[String: Any]] = []
    var failures = 0

    for (index, app) in targets.enumerated() {
        if index > 0, options.delay > 0 {
            try await Task.sleep(for: .milliseconds(options.delay))
        }
        if interactive, !options.json { progress(index, targets.count, app.pkg) }

        do {
            let data = try await store.iconData(app, size: options.size)
            let icon = try await IconRenderer.render(
                data, size: options.size, upscale: options.upscale)
            let stem = "\(PlayApp.sanitizedFileName(app.pkg))_\(icon.pixels)"
            let url = uniqueURL(in: directory, stem: stem)
            try icon.data.write(to: url, options: .atomic)
            written.append([
                "pkg": app.pkg, "name": app.name, "pixels": icon.pixels, "path": url.path,
            ])
            if !options.json, !interactive {
                print(url.path)
            }
        } catch {
            failures += 1
            note("\rkiosk: \(app.pkg): \(error.localizedDescription)")
        }
    }

    if interactive, !options.json {
        progress(targets.count, targets.count, "done")
        note("")
        for row in written {
            let pixels = row["pixels"] as? Int ?? 0
            let short = pixels < options.size && !options.upscale ? "  (store max \(pixels)px)" : ""
            print("\(row["path"] as? String ?? "")\(short)")
        }
    }

    if options.json {
        let data = try JSONSerialization.data(
            withJSONObject: written, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    exit(failures > 0 && written.isEmpty ? 1 : 0)
} catch {
    fail(error.localizedDescription)
}
