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

        print("\(total - failures)/\(total) passed")
        if failures > 0 {
            exit(1)
        }
    }
}
