import Foundation

@main
struct Tests {
    static var failures = 0
    static var total = 0

    static func check(
        _ name: String, _ condition: @autoclosure () -> Bool,
        _ detail: @autoclosure () -> String = ""
    ) {
        total += 1
        if condition() {
            print("ok - \(name)")
        } else {
            failures += 1
            print("FAIL - \(name): \(detail())")
        }
    }

    static func makeApp(icon: String, source: StoreSource) -> PlayApp {
        PlayApp(pkg: "pkg", name: "name", developer: "dev", rating: "4.5", icon: icon, source: source)
    }

    static func main() {
        // sanitizedFileName

        check("sanitize keeps normal package name",
            PlayApp.sanitizedFileName("com.spotify.music") == "com.spotify.music")

        check("sanitize dots collapse to icon",
            PlayApp.sanitizedFileName("..") == "icon")

        let traversal = PlayApp.sanitizedFileName("../../etc/passwd")
        check("sanitize traversal has no slash",
            !traversal.contains("/"), traversal)
        check("sanitize traversal has no leading dot",
            !traversal.hasPrefix("."), traversal)

        check("sanitize slash becomes dash",
            PlayApp.sanitizedFileName("a/b") == "a-b")

        check("sanitize empty becomes icon",
            PlayApp.sanitizedFileName("") == "icon")

        let long = String(repeating: "a", count: 200)
        let sanitizedLong = PlayApp.sanitizedFileName(long)
        check("sanitize caps at 80 chars",
            sanitizedLong.count == 80, "got \(sanitizedLong.count)")

        let unicodeInput = "héllo🎉wörld_😀.txt"
        let sanitizedUnicode = PlayApp.sanitizedFileName(unicodeInput)
        let allowedSet = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        check("sanitize unicode yields only allowed chars",
            sanitizedUnicode.unicodeScalars.allSatisfy { allowedSet.contains($0) }, sanitizedUnicode)

        check("sanitize symbols-only becomes icon",
            PlayApp.sanitizedFileName("!@#$%^&*()") == "icon")

        // isAllowedIconHost

        check("host allows play-lh.googleusercontent.com",
            PlayApp.isAllowedIconHost(URL(string: "https://play-lh.googleusercontent.com/abc")!))

        check("host allows mzstatic.com subdomain",
            PlayApp.isAllowedIconHost(URL(string: "https://is1-ssl.mzstatic.com/image/thumb/x.png")!))

        check("host rejects non-https",
            !PlayApp.isAllowedIconHost(URL(string: "http://play-lh.googleusercontent.com/abc")!))

        check("host rejects unrelated domain",
            !PlayApp.isAllowedIconHost(URL(string: "https://evil.com/x")!))

        check("host rejects lookalike suffix domain",
            !PlayApp.isAllowedIconHost(URL(string: "https://play-lh.googleusercontent.com.evil.com/x")!))

        // sized()

        let playApp = makeApp(icon: "https://play-lh.googleusercontent.com/abc123", source: .play)
        if let url = playApp.sized(512) {
            check("sized play URL ends with size suffix", url.absoluteString.hasSuffix("=s512-rw"), url.absoluteString)
        } else {
            check("sized play URL ends with size suffix", false, "sized returned nil")
        }

        let appStoreApp = makeApp(icon: "https://is1-ssl.mzstatic.com/image/thumb/abc", source: .appStore)
        if let url = appStoreApp.sized(512) {
            check("sized appStore URL ends with size path", url.absoluteString.hasSuffix("/512x512bb.png"), url.absoluteString)
        } else {
            check("sized appStore URL ends with size path", false, "sized returned nil")
        }

        let malformedApp = makeApp(icon: "not a url", source: .play)
        check("sized returns nil for malformed base",
            malformedApp.sized(512) == nil)

        let disallowedHostApp = makeApp(icon: "https://evil.com/abc", source: .play)
        check("sized returns nil for disallowed host",
            disallowedHostApp.sized(512) == nil)

        func response(_ code: Int, retryAfter: String?) -> HTTPURLResponse {
            var headers: [String: String] = [:]
            if let retryAfter { headers["Retry-After"] = retryAfter }
            return HTTPURLResponse(
                url: URL(string: "https://play.google.com/")!, statusCode: code,
                httpVersion: nil, headerFields: headers)!
        }

        check("429 is retryable", PlayStore.retryable.contains(429))
        check("503 is retryable", PlayStore.retryable.contains(503))
        check("404 is not retryable", !PlayStore.retryable.contains(404))

        let numeric = PlayStore.retryDelay(response(429, retryAfter: "3"), attempt: 0)
        check("Retry-After seconds honoured", numeric == 3, "\(numeric)")

        let clamped = PlayStore.retryDelay(response(429, retryAfter: "9999"), attempt: 0)
        check("Retry-After clamped to a minute", clamped == 60, "\(clamped)")

        let negative = PlayStore.retryDelay(response(429, retryAfter: "-5"), attempt: 0)
        check("negative Retry-After floors at zero", negative == 0, "\(negative)")

        let httpDate = PlayStore.retryDelay(
            response(503, retryAfter: "Wed, 21 Oct 2015 07:28:00 GMT"), attempt: 0)
        check("past HTTP date yields no wait", httpDate == 0, "\(httpDate)")

        let garbage = PlayStore.retryDelay(response(429, retryAfter: "soon"), attempt: 1)
        check("garbage Retry-After backs off", garbage >= 2 && garbage <= 2.4, "\(garbage)")

        let backoff0 = PlayStore.retryDelay(response(500, retryAfter: nil), attempt: 0)
        let backoff2 = PlayStore.retryDelay(response(500, retryAfter: nil), attempt: 2)
        check("backoff grows with attempts", backoff0 < backoff2, "\(backoff0) \(backoff2)")

        let capped = PlayStore.retryDelay(response(500, retryAfter: nil), attempt: 9)
        check("backoff capped at eight seconds", capped <= 8.4, "\(capped)")

        print("\(total - failures)/\(total) passed")
        if failures > 0 {
            exit(1)
        }
    }
}
