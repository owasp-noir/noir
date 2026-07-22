import Foundation

// Compact single-line enum with implicit raw values — a naive
// `depth = count('{') - count('}')` check on the declaration line alone
// nets to 0 here (open and close on the same line) and used to bail out
// with zero harvested cases.
enum CompactHost: String { case alpha, beta, gamma }

func routeCompact(_ url: URL) {
    if url.host == CompactHost.alpha.rawValue {
        openAlpha()
    }
}

// The last case's raw value contains "//" and shares its line with the
// enum's own closing brace — a naive `line.sub(/\/\/.*$/, "")` comment
// stripper truncates the line (and the value) at the "//" inside the
// string, silently dropping this case and losing track of the closing
// brace along with it.
enum TrickyHost: String {
    case normal
    case legacy = "notes//path" }

func routeTricky(_ url: URL) {
    if url.host == TrickyHost.normal.rawValue {
        openNormal()
    }
}

// `[...].contains(url.host)` membership form, not a direct `==`.
enum ContainsHost: String { case digitalcard, digitaldocs, me }

func routeContains(_ url: URL) {
    if [ContainsHost.digitalcard.rawValue, ContainsHost.digitaldocs.rawValue].contains(url.host) {
        openContains()
    }
}

// An unrelated capitalized enum's `.rawValue` sharing a line with an
// unrelated `.host` token must not be mistaken for a routing comparison.
enum LoggerLevel: String { case debug, info, warn, error }

func unrelatedHostCheck(_ response: URLResponse, _ threshold: Int) {
    if response.url?.host == expectedHost() && LoggerLevel.debug.rawValue.count >= threshold {
        noop()
    }
}

func openAlpha() {}
func openNormal() {}
func openContains() {}
func expectedHost() -> String { "" }
func noop() {}
