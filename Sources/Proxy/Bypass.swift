import Foundation

final class BypassManager {
    private let hosts: Set<String>

    init(storageDirectory: URL) {
        var parsed = Set<String>()

        // env var: comma-separated list
        if let env = ProcessInfo.processInfo.environment["REEDPIPE_BYPASS_HOSTS"] {
            env.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.forEach { s in
                if !s.isEmpty { parsed.insert(s) }
            }
        }

        // file: storageDirectory/bypass.txt (one host per line)
        let fileURL = storageDirectory.appendingPathComponent("bypass.txt")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
                text.split{ $0 == "\n" || $0 == "\r" }.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.forEach { s in
                    if !s.isEmpty { parsed.insert(s) }
                }
            }
        }

        self.hosts = parsed
    }

    func contains(_ host: String) -> Bool {
        return hosts.contains(host)
    }
}
