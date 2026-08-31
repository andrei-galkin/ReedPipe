import Foundation
import Crypto
import X509
import SwiftASN1
import NIOSSL
import NIOConcurrencyHelpers

/// Generates and persists a local root CA, and mints a leaf certificate
/// (signed by that CA) covering every HTTPS host the proxy has seen so far.
///
/// Why "every host in one certificate" instead of a fresh certificate per
/// host, selected via SNI: NIOSSL doesn't currently expose a per-connection
/// SNI callback — the underlying BoringSSL
/// `SSL_CTX_set_tlsext_servername_callback` isn't wired up
/// (https://github.com/apple/swift-nio-ssl/issues/310, open since 2021).
/// Implementing that ourselves would mean hand-parsing the raw ClientHello
/// bytes to read the SNI extension before NIOSSL ever sees them — real
/// TLS-record-level parsing, high risk to get right without being able to
/// test it directly. Instead: one certificate, whose Subject Alternative
/// Name list grows to cover every host visited, re-minted (and the
/// NIOSSLContext rebuilt) each time a genuinely new host shows up. Browsers
/// only check that the presented certificate's SAN list covers the host
/// they're connecting to — they don't require the certificate to have been
/// chosen "for" their specific SNI value — so this satisfies certificate
/// validation for every covered host equally.
final class CertificateAuthority {
    /// Covers small clock differences and certificate timestamp precision.
    private static let validitySkewAllowance: TimeInterval = 5 * 60

    private let caCertificate: Certificate
    private let caPrivateKey: Certificate.PrivateKey
    private let storageDirectory: URL

    private let lock = NIOLock()
    private var knownHosts: Set<String> = []
    private var cachedContext: NIOSSLContext?

    init(storageDirectory: URL) throws {
        self.storageDirectory = storageDirectory
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)

        let certURL = storageDirectory.appendingPathComponent("ReedPipeRootCA.pem")
        let keyURL = storageDirectory.appendingPathComponent("ReedPipeRootCA.key.pem")

        if let existing = try Self.loadExistingCA(certURL: certURL, keyURL: keyURL) {
            self.caCertificate = existing.certificate
            self.caPrivateKey = existing.privateKey
        } else {
            let generated = try Self.generateCA()
            self.caCertificate = generated.certificate
            self.caPrivateKey = generated.privateKey
            try Self.save(certificate: generated.certificate, to: certURL)
            try Self.save(text: generated.privateKeyPEM, to: keyURL)
        }
    }

    /// Path to the root CA certificate (PEM) — install and trust this on
    /// whatever machine's browser you're pointing at the proxy. Never share
    /// the accompanying `.key.pem` file; it can sign a certificate for any
    /// domain, for anyone who has it.
    var rootCertificatePath: String {
        storageDirectory.appendingPathComponent("ReedPipeRootCA.pem").path
    }

    /// Ensures `host` is covered by the current leaf certificate, minting a
    /// new one (with this host added to its SAN list) and rebuilding the
    /// NIOSSLContext if it isn't yet covered. Returns the context to use
    /// for the TLS handshake with this (and every other currently-covered)
    /// host.
    func context(for host: String) throws -> NIOSSLContext {
        try lock.withLock {
            if cachedContext == nil || !knownHosts.contains(host) {
                knownHosts.insert(host)
                cachedContext = try Self.buildLeafContext(
                    hosts: knownHosts,
                    caCertificate: caCertificate,
                    caPrivateKey: caPrivateKey
                )
            }
            return cachedContext!
        }
    }

    // MARK: - CA generation / persistence

    private static func generateCA() throws -> (certificate: Certificate, privateKey: Certificate.PrivateKey, privateKeyPEM: String) {
        let swiftCryptoKey = P256.Signing.PrivateKey()
        let key = Certificate.PrivateKey(swiftCryptoKey)

        let name = try DistinguishedName {
            CommonName("ReedPipe Local Root CA")
            OrganizationName("ReedPipe (locally generated — do not distribute)")
        }

        let now: Date = .init()
        let validFrom: Date = now.addingTimeInterval(-Self.validitySkewAllowance)
        let extensions = try Certificate.Extensions {
            Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
            Critical(KeyUsage(keyCertSign: true, cRLSign: true))
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: key.publicKey,
            notValidBefore: validFrom,
            notValidAfter: now.addingTimeInterval(60 * 60 * 24 * 365 * 5), // 5 years
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: key
        )

        return (certificate, key, swiftCryptoKey.pemRepresentation)
    }

    private static func loadExistingCA(certURL: URL, keyURL: URL) throws -> (certificate: Certificate, privateKey: Certificate.PrivateKey)? {
        guard FileManager.default.fileExists(atPath: certURL.path),
              FileManager.default.fileExists(atPath: keyURL.path) else {
            return nil
        }
        let certPEM = try String(contentsOf: certURL, encoding: .utf8)
        let keyPEM = try String(contentsOf: keyURL, encoding: .utf8)

        let certificate = try Certificate(pemEncoded: certPEM)
        let swiftCryptoKey = try P256.Signing.PrivateKey(pemRepresentation: keyPEM)
        return (certificate, Certificate.PrivateKey(swiftCryptoKey))
    }

    private static func save(certificate: Certificate, to url: URL) throws {
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        let pem = PEMDocument(type: "CERTIFICATE", derBytes: serializer.serializedBytes).pemString
        try Self.save(text: pem, to: url)
    }

    private static func save(text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: - Leaf certificate minting

    private static func buildLeafContext(
        hosts: Set<String>,
        caCertificate: Certificate,
        caPrivateKey: Certificate.PrivateKey
    ) throws -> NIOSSLContext {
        let leafSwiftCryptoKey = P256.Signing.PrivateKey()
        let leafKey = Certificate.PrivateKey(leafSwiftCryptoKey)

        let subjectName = try DistinguishedName {
            CommonName(hosts.first ?? "reedpipe.local")
        }

        let sanNames: [GeneralName] = hosts.map { .dnsName($0) }
        let extensions = try Certificate.Extensions {
            Critical(BasicConstraints.notCertificateAuthority)
            Critical(KeyUsage(digitalSignature: true, keyEncipherment: true))
            try ExtendedKeyUsage([.serverAuth])
            SubjectAlternativeNames(sanNames)
        }

        let now: Date = .init()
        let validFrom: Date = now.addingTimeInterval(-Self.validitySkewAllowance)
        let leafCertificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: leafKey.publicKey,
            notValidBefore: validFrom,
            // Short-lived on purpose — this cert gets rebuilt whenever a new
            // host shows up anyway, so there's no benefit to a long lifetime,
            // and a short one limits exposure if the storage directory leaks.
            notValidAfter: now.addingTimeInterval(60 * 60 * 24 * 30),
            issuer: caCertificate.subject,
            subject: subjectName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: caPrivateKey
        )

        var leafSerializer = DER.Serializer()
        try leafSerializer.serialize(leafCertificate)
        let leafDER = leafSerializer.serializedBytes

        var caSerializer = DER.Serializer()
        try caSerializer.serialize(caCertificate)
        let caDER = caSerializer.serializedBytes

        let nioLeafCert = try NIOSSLCertificate(bytes: leafDER, format: .der)
        let nioCACert = try NIOSSLCertificate(bytes: caDER, format: .der)
        let nioLeafKey = try NIOSSLPrivateKey(bytes: Array(leafSwiftCryptoKey.derRepresentation), format: .der)

        var tlsConfig = TLSConfiguration.makeServerConfiguration(
            certificateChain: [.certificate(nioLeafCert), .certificate(nioCACert)],
            privateKey: .privateKey(nioLeafKey)
        )
        tlsConfig.minimumTLSVersion = .tlsv12

        return try NIOSSLContext(configuration: tlsConfig)
    }
}
