import Foundation

enum StoreSource: String, CaseIterable, Identifiable {
    case play, appStore

    var id: String { rawValue }

    var label: String { self == .play ? "Google Play" : "App Store" }
}

struct PlayApp: Identifiable, Hashable {
    let pkg: String
    let name: String
    let developer: String
    let rating: String
    let icon: String
    var source: StoreSource = .play

    var id: String { "\(source.rawValue)|\(pkg)" }

    func sized(_ size: Int) -> URL? {
        let string: String
        switch source {
        case .play: string = "\(icon)=s\(size)-rw"
        case .appStore: string = "\(icon)/\(size)x\(size)bb.png"
        }
        guard let url = URL(string: string), Self.isAllowedIconHost(url) else { return nil }
        return url
    }

    static func isAllowedIconHost(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host else { return false }
        let allowedSuffixes = ["play-lh.googleusercontent.com", "mzstatic.com"]
        return allowedSuffixes.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    static func sanitizedFileName(_ raw: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        var result = ""
        result.reserveCapacity(raw.count)
        for scalar in raw.unicodeScalars {
            result.unicodeScalars.append(allowed.contains(scalar) ? scalar : "-")
        }
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        while let first = result.first, first == "." || first == "-" {
            result.removeFirst()
        }
        while let last = result.last, last == "-" {
            result.removeLast()
        }
        if result.count > 80 {
            result = String(result.prefix(80))
            while let last = result.last, last == "-" {
                result.removeLast()
            }
        }
        return result.isEmpty ? "icon" : result
    }
}

private struct ITunesResponse: Decodable {
    struct Result: Decodable {
        let bundleId: String
        let trackName: String
        let artistName: String
        let averageUserRating: Double?
        let artworkUrl512: String?
        let artworkUrl100: String?
    }

    let results: [Result]
}

enum PlayStoreError: Error, LocalizedError {
    case badStatus(Int)
    case rateLimited
    case badIconURL
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "Store returned HTTP \(code)"
        case .rateLimited: return "Rate limited by the store; try again with a longer --delay"
        case .badIconURL: return "Icon URL is invalid or not from a trusted host"
        case .tooLarge: return "Response exceeded the maximum allowed size"
        }
    }
}

actor PlayStore {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36",
            "Accept-Language": "en-US,en",
        ]
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private static let link = try! NSRegularExpression(
        pattern: #"href="/store/apps/details\?id=([A-Za-z0-9._]+)""#)
    private static let label = try! NSRegularExpression(pattern: #"^\s*aria-label="([^"]*)""#)
    private static let title = try! NSRegularExpression(
        pattern: #"<span class="DdYX5[^"]*">([^<]+)</span>"#)
    private static let developer = try! NSRegularExpression(
        pattern: #"<span class="wMUdtb[^"]*">([^<]+)</span>"#)
    private static let rating = try! NSRegularExpression(
        pattern: #"<span class="w2kbF[^"]*">([^<]+)</span>"#)
    private static let icon = try! NSRegularExpression(
        pattern: #"https://play-lh\.googleusercontent\.com/([A-Za-z0-9_-]+)=s\d+"#)

    func search(
        _ query: String, source: StoreSource, country: String = "us", limit: Int = 30
    ) async throws -> [PlayApp] {
        switch source {
        case .play: try await searchPlay(query, country: country, limit: limit)
        case .appStore: try await searchAppStore(query, country: country, limit: limit)
        }
    }

    private func searchAppStore(
        _ query: String, country: String, limit: Int
    ) async throws -> [PlayApp] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            .init(name: "term", value: query),
            .init(name: "entity", value: "software"),
            .init(name: "country", value: country),
            .init(name: "limit", value: "\(limit)"),
        ]
        let response = try JSONDecoder().decode(
            ITunesResponse.self, from: try await data(from: components.url!))

        return response.results.compactMap { result in
            guard let art = result.artworkUrl512 ?? result.artworkUrl100,
                  let artURL = URL(string: art), PlayApp.isAllowedIconHost(artURL),
                  let base = art.range(of: "/", options: .backwards).map({ String(art[..<$0.lowerBound]) })
            else { return nil }
            let rating = result.averageUserRating.map { String(format: "%.1f", $0) } ?? ""
            return PlayApp(
                pkg: result.bundleId,
                name: result.trackName,
                developer: result.artistName,
                rating: rating,
                icon: base,
                source: .appStore)
        }
    }

    private func searchPlay(
        _ query: String, country: String, limit: Int
    ) async throws -> [PlayApp] {
        var components = URLComponents(string: "https://play.google.com/store/search")!
        components.queryItems = [
            .init(name: "q", value: query),
            .init(name: "c", value: "apps"),
            .init(name: "hl", value: "en"),
            .init(name: "gl", value: country),
        ]
        let html = try await text(from: components.url!)

        var apps: [PlayApp] = []
        var seen = Set<String>()
        let full = NSRange(html.startIndex..., in: html)

        for match in Self.link.matches(in: html, range: full) {
            guard let pkg = capture(1, match, html), seen.insert(pkg).inserted else { continue }
            let start = match.range.upperBound
            let end = min(start + 6000, full.length)
            let segment = NSRange(location: start, length: end - start)

            guard let iconMatch = Self.icon.firstMatch(in: html, range: segment),
                  let hash = capture(1, iconMatch, html)
            else { continue }

            let name = firstCapture(Self.label, in: html, range: segment)
                ?? firstCapture(Self.title, in: html, range: segment)
                ?? pkg

            apps.append(PlayApp(
                pkg: pkg,
                name: unescape(name),
                developer: unescape(firstCapture(Self.developer, in: html, range: segment) ?? ""),
                rating: firstCapture(Self.rating, in: html, range: segment)?
                    .trimmingCharacters(in: .whitespaces) ?? "",
                icon: "https://play-lh.googleusercontent.com/\(hash)"))

            if apps.count >= limit { break }
        }
        return apps
    }

    func iconData(_ app: PlayApp, size: Int) async throws -> Data {
        guard let url = app.sized(size) else { throw PlayStoreError.badIconURL }
        return try await data(from: url)
    }

    private func data(from url: URL, maxBytes: Int = 8 * 1024 * 1024) async throws -> Data {
        var attempt = 0
        while true {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                if Self.retryable.contains(http.statusCode), attempt < 3 {
                    let wait = Self.retryDelay(http, attempt: attempt)
                    attempt += 1
                    try await Task.sleep(for: .seconds(wait))
                    continue
                }
                if http.statusCode == 429 { throw PlayStoreError.rateLimited }
                throw PlayStoreError.badStatus(http.statusCode)
            }
            if response.expectedContentLength > Int64(maxBytes) || data.count > maxBytes {
                throw PlayStoreError.tooLarge
            }
            return data
        }
    }

    static let retryable: Set<Int> = [429, 500, 502, 503, 504]

    static func retryDelay(_ response: HTTPURLResponse, attempt: Int) -> Double {
        if let header = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = Double(header.trimmingCharacters(in: .whitespaces)) {
                return min(max(seconds, 0), 60)
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: header) {
                return min(max(date.timeIntervalSinceNow, 0), 60)
            }
        }
        return min(pow(2, Double(attempt)), 8) + Double.random(in: 0...0.4)
    }

    private func text(from url: URL) async throws -> String {
        let data = try await data(from: url, maxBytes: 20 * 1024 * 1024)
        return String(decoding: data, as: UTF8.self)
    }

    private func capture(_ index: Int, _ match: NSTextCheckingResult, _ text: String) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    private func firstCapture(
        _ regex: NSRegularExpression, in text: String, range: NSRange
    ) -> String? {
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return capture(1, match, text)
    }

    private func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
    }
}
