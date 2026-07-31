import Foundation
import NIO

@main
struct ProxyMain {
    static func main() throws {
        let host = "127.0.0.1"
        let port = 8080

        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        defer {
            try? group.syncShutdownGracefully()
        }

        let caStorageDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".reedpipe", isDirectory: true)

        do {
            let certificateAuthority = try CertificateAuthority(storageDirectory: caStorageDirectory)
            let bypassManager = BypassManager(storageDirectory: caStorageDirectory)
            let server = ProxyServer(group: group, certificateAuthority: certificateAuthority, bypassManager: bypassManager)

            let channel = try server.start(host: host, port: port).wait()
            print("HTTP proxy listening on \(host):\(port)")
            print("Test it with: curl -x http://\(host):\(port) http://example.com")
            print("Live frame feed: ws://\(host):\(port)\(ProxyServer.webSocketPath)")
            print("")
            print("HTTPS interception: to inspect HTTPS traffic, trust this root CA")
            print("certificate on the machine whose browser/client points at the proxy:")
            print("    \(certificateAuthority.rootCertificatePath)")
            print("Never share the accompanying .key.pem file — it can sign a")
            print("certificate for any domain, for anyone who has it.")
            try channel.closeFuture.wait()
        } catch {
            print("Failed to start proxy: \(error)")
            exit(1)
        }
    }
}