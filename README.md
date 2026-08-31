# ReedPipe

ReedPipe — A lightweight, local-first HTTP traffic inspector built with native Swift (SwiftNIO) and a Swift/WebAssembly browser frontend.

Point your tools (or your browser) at ReedPipe as an HTTP/HTTPS proxy, and watch every request and response — headers, bodies, status, timing — appear live in a browser-based session view. No traffic leaves your machine; there's no cloud component, no third-party service, nothing to sign up for.

## How it works

```
Test client (curl / browser)
        │    configured to use ReedPipe as its proxy
        ▼
Proxy (native Swift, SwiftNIO) — listens on 127.0.0.1:8080
  • Plain HTTP: parses the absolute-form request, forwards it, captures
    the request/response pair
  • HTTPS (CONNECT): terminates TLS itself using a certificate minted by
    a local root CA, decrypts, parses, forwards to the real origin over a
    fresh outbound TLS connection, and captures the pair the same way
  • Serializes each captured exchange into a JSON "frame" and broadcasts
    it over a WebSocket at ws://127.0.0.1:8080/ws
        │
        ▼
Frontend (Swift compiled to WebAssembly + JavaScriptKit)
  • Connects to the WebSocket feed and decodes each frame into the shared
    Core model without linking Foundation or Codable into Wasm
  • Renders a live, append-only session table: Method / Host / Path /
    Status / Content-Type / Size / Duration
  • Each row expands (native <details>) to show full request/response
    headers and bodies, with JSON bodies pretty-printed
```

Three targets share one Swift package:

- **Core** — the `TrafficFrame` model and related types. It has no platform-specific dependencies; native builds add `Codable`, while the Wasm frontend uses its lightweight JavaScriptKit decoder.
- **Proxy** — the SwiftNIO server: HTTP/HTTPS capture, the WebSocket broadcast, and the local certificate authority for HTTPS interception.
- **Frontend** — the Wasm module that runs in the browser and renders the live session view.

## Project structure

```
ReedPipe/
├── Package.swift
├── Sources/
│   ├── Core/
│   │   ├── TrafficFrame.swift         # The captured request/response frame
│   │   ├── CapturedRequest.swift
│   │   ├── CapturedResponse.swift
│   │   ├── CapturedHeader.swift
│   │   ├── BodyEncoder.swift          # UTF-8 vs base64 body encoding
│   │   └── FrameCoding.swift          # Shared JSON encoder/decoder config
│   ├── Proxy/
│   │   ├── Main.swift                 # Entry point; starts the CA + server
│   │   ├── ProxyServer.swift          # Bootstraps the listening socket
│   │   ├── FrontendHandler.swift      # Client-facing: HTTP forward + CONNECT/TLS upgrade
│   │   ├── TunneledHTTPHandler.swift  # Parses decrypted HTTPS traffic inside a tunnel
│   │   ├── BackendHandler.swift       # Outbound leg: replays the request, captures the response
│   │   ├── CertificateAuthority.swift # Local root CA + per-host leaf cert minting
│   │   ├── FrameSink.swift            # Where captured frames leave the pipeline
│   │   ├── FrameBroadcaster.swift     # Tracks connected WebSocket clients
│   │   └── WebSocketHandler.swift     # Per-connection WebSocket housekeeping
│   └── Frontend/
│       ├── App.swift                  # Wasm entry point
│       ├── SessionController.swift    # Wires WebSocket + store + renderer together
│       ├── WebSocketClient.swift      # Connects to /ws, reconnects with backoff
│       ├── SessionStore.swift         # In-memory frame store
│       ├── SessionListRenderer.swift  # Builds the live DOM table
│       ├── DetailFormatting.swift     # Body/header formatting, JSON pretty-printing
│       └── JSHelpers.swift            # Centralized JavaScriptKit call patterns
├── Tests/
│   └── CoreTests/
│       └── TrafficFrameTests.swift
├── Public/
│   └── index.html                     # Page shell that loads the compiled Wasm module
└── README.md
```

## Prerequisites

- **Swift 6.2+**, installed via [swiftly](https://swift.org/swiftly) or the official swift.org toolchain (this project was built and tested against **Swift 6.3.3**)
- The matching **Wasm Swift SDK** for your exact toolchain version (see setup below)
- `curl` and (optionally) a browser for testing — Firefox instructions are included below since Firefox uses its own certificate store separate from the OS

## Setup

### 1. Install the Wasm Swift SDK

The Frontend target compiles to `wasm32-unknown-wasi`, which needs a separately-installed SDK matching your exact Swift version:

```bash
swift --version   # confirm your exact version, e.g. Swift version 6.3.3 (swift-6.3.3-RELEASE)

# substitute your version below if it differs from 6.3.3 — URL and checksum
# must match exactly; find both at https://www.swift.org/install
swift sdk install https://download.swift.org/swift-6.3.3-release/wasm-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_wasm.artifactbundle.tar.gz --checksum cabfa08b73bb8ac783927ecd15fa386e99d0c139c5f232445067bcf58379cae7

swift sdk list   # confirm it installed — note the exact SDK id it prints
```

### 2. Build the Proxy (native)

```bash
swift build --target Proxy
```

### 3. Build and package the Frontend (Wasm)

```bash
swift build --scratch-path .build/wasm --target Frontend --swift-sdk <your-sdk-id-from-above>
swift package --scratch-path .build/wasm --swift-sdk <your-sdk-id-from-above> js --use-cdn --product Frontend
```

The separate Wasm scratch directory prevents SwiftPM's cross-compilation build plan from replacing the native plan used by `swift build --target Proxy` and `swift run Proxy`. The second command uses JavaScriptKit's `PackageToJS` plugin to produce a ready-to-serve bundle at `.build/wasm/plugins/PackageToJS/outputs/Package/` — `Public/index.html` already points at this path, so no manual file copying is needed.

> Don't run plain `swift build` or `swift test` with no target/filter on a machine that only has the native toolchain installed — it'll try to build the Wasm-only `Frontend` target too and fail. Always scope commands with `--target`/`--filter` until the Wasm SDK is set up.

## Running

**Terminal 1 — the proxy:**

```bash
swift run Proxy
```

On first run this generates a local root CA under `~/.reedpipe/` and prints its path — you'll need it for HTTPS interception (see below). On later runs the existing CA is reused.

**Terminal 2 — serve the frontend:**

```bash
python3 -m http.server 8000
```

Open `http://localhost:8000/Public/index.html` — the status line should read "Connected — live".

**Terminal 3 — generate traffic:**

```bash
# plain HTTP
curl -x http://127.0.0.1:8080 http://neverssl.com

# HTTPS — trust the CA for just this one command with --cacert
curl -x http://127.0.0.1:8080 --cacert ~/.reedpipe/ReedPipeRootCA.pem https://neverssl.com
```

To generate 20 monitored GET, POST, and DELETE requests (10 HTTP and 10 HTTPS)
with JSON request bodies, timeouts, one intentional upstream connection
failure, one intentional HTTP 503 response, and a summary, run:

```bash
./Scripts/generate-test-traffic.sh
```

Each request should appear as a new row in the browser tab. Click **View** in
the Response column to inspect the complete status line, headers, and body in a
modal dialog. Binary bodies are displayed as Base64.

## Inspecting your browser's traffic

To route a real browser through ReedPipe (rather than just `curl`), you need to both point it at the proxy **and** trust the CA certificate — Firefox keeps its own certificate store, separate from the OS:

1. **Import and trust the CA:** `about:preferences#privacy` → **Certificates** → **View Certificates...** → **Authorities** tab → **Import...** → select `~/.reedpipe/ReedPipeRootCA.pem` → check **"Trust this CA to identify websites"**
2. **Set the proxy:** `about:preferences#general` → **Network Settings** → **Settings...** → **Manual proxy configuration** → HTTP Proxy `127.0.0.1` port `8080`, and check **"Also use this proxy for HTTPS"**
3. Browse to a site and watch it show up live in the ReedPipe tab

When you're done, switch the proxy setting back to "Use system proxy settings" — otherwise all your browsing keeps trying to route through the proxy even after you stop it.

## Known limitations

- **A small number of sites can never work through any local MITM proxy, by design.** Domains on Firefox/Chrome's built-in HSTS-preload list (YouTube, Google, and similar high-value domains) hard-block interception at the browser binary level, with no override — this is intentional browser security policy, not a ReedPipe bug, and every tool in this category (mitmproxy, Charles, Fiddler) hits the same wall.
- **No HTTP keep-alive over HTTPS tunnels.** Each captured request closes the tunnel afterward, so real browsing through the proxy is slower and more chatty (repeated TLS handshakes) than normal — capture correctness isn't affected, just performance.
- **One certificate covers every host, rather than one-per-host via SNI.** `swift-nio-ssl` doesn't currently support per-connection certificate selection ([issue #310](https://github.com/apple/swift-nio-ssl/issues/310)), so ReedPipe mints a single certificate whose Subject Alternative Name list grows to cover every host visited, re-minted when a new host shows up. Functionally equivalent from the browser's point of view, but not how a "real" MITM proxy like mitmproxy is built internally.
- **IPv6 literal CONNECT targets** (e.g. `[::1]:443`) aren't parsed correctly — low priority since browsers overwhelmingly send hostnames.
- **The CA's private key file (`~/.reedpipe/ReedPipeRootCA.key.pem`) can sign a trusted certificate for any domain.** Never share it, and treat trusting the CA the same way you'd treat installing any other MITM tool's root certificate.

## Running the tests

```bash
swift test --filter CoreTests
```

## Acknowledgements

This project was created during the official [Swift Mentorship Program](https://www.swift.org/mentorship/).
