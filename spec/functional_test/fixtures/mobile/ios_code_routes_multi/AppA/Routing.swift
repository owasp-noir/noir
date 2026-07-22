import Foundation

enum SharedHost: String {
    case foo
}

func check(_ url: URL) {
    if url.host == SharedHost.foo.rawValue {
        handle()
    }
}
