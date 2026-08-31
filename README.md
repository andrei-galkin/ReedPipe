# ReedPipe

ReedPipe is a local HTTP/HTTPS debugging proxy written in Swift. It captures
traffic with SwiftNIO and streams completed exchanges to a browser frontend
written in Swift and compiled to WebAssembly.

ReedPipe has no account, cloud service, or telemetry. Captured data stays in
the local proxy and browser process; proxied requests still travel to their
original destination servers.

## Features

- Inspects plain HTTP proxy requests.
- Intercepts HTTPS `CONNECT` tunnels with a locally generated root CA.
- Streams completed requests, responses, failures, and timings over WebSocket.
- Shows a live table with colored GET, PUT, PATCH, POST, and DELETE badges.
- Opens completed responses in a modal as a reconstructed HTTP status line,
  headers, and body.
- Displays binary response bodies as Base64.
- Reports upstream connection failures and response timeouts in the table.
- Keeps `Core` and `Frontend` free of Foundation; browser interop remains in
  the `Frontend` target.

## Architecture

```text
Client configured to use 127.0.0.1:8080
                    │
                    ▼
Native Swift proxy (SwiftNIO)
  HTTP  ──────────► origin server
  HTTPS ─► local TLS termination ─► origin TLS server
                    │
                    └─ captured JSON frames
                              │
                              ▼ ws://127.0.0.1:8080/ws
                    Swift/WebAssembly frontend
```

The browser monitor is live-only. It does not persist or replay exchanges made
before the frontend reaches `Connected — live`.

The Swift package contains three targets:

- `Core` — Foundation-free capture models, body encoding, and raw-response
  formatting. Native builds add `Codable`; WASI builds exclude it.
- `Proxy` — the native SwiftNIO proxy, WebSocket broadcaster, timeout handling,
  HTTPS interception, CA management, and optional tunnel bypass.
- `Frontend` — the JavaScriptKit/WebAssembly client, in-memory session store,
  table renderer, and response dialog.

## Repository layout

```text
ReedPipe/
├── Package.swift
├── Sources/
│   ├── Core/       # Shared capture models and formatters
│   ├── Proxy/      # Native proxy, TLS interception, and WebSocket feed
│   └── Frontend/   # Swift/WebAssembly browser application
├── Public/
│   └── index.html  # Page shell and styles
├── Scripts/
│   └── generate-test-traffic.sh
└── Tests/
    └── CoreTests/
```

## Requirements

- Swift 6.2 or newer. The project is currently validated with Swift 6.2.
- A WebAssembly Swift SDK matching the installed Swift toolchain.
- `curl` for the smoke test.
- Python 3 or another static HTTP server for the browser frontend.

## Quick start

### 1. Install or select the WebAssembly SDK

Check the native toolchain and installed SDKs:

```bash
swift --version
swift sdk list
```

If no matching `_wasm` SDK is listed, download the WebAssembly SDK for the
exact Swift release from [swift.org/install](https://www.swift.org/install/)
and follow its `swift sdk install` command. The Swift toolchain and SDK release
must match.

Set the identifier printed by `swift sdk list`. For example, with Swift 6.2:

```bash
WASM_SDK=swift-6.2-RELEASE_wasm
```

Do not type explanatory placeholders such as `<your-sdk-id>` directly into
Bash; angle brackets are shell redirection operators.

### 2. Build the proxy and browser bundle

From the repository root:

```bash
swift build --target Proxy

swift package \
  --scratch-path .build/wasm \
  --swift-sdk "$WASM_SDK" \
  js --use-cdn --product Frontend
```

The JavaScriptKit packaging command builds the frontend and writes the
browser-ready bundle to:

```text
.build/wasm/plugins/PackageToJS/outputs/Package/
```

`Public/index.html` imports that bundle directly. The separate Wasm scratch
directory prevents the cross-compilation build plan from replacing the native
proxy build plan.

### 3. Start ReedPipe

Terminal 1 — run the proxy:

```bash
swift run Proxy
```

The proxy listens on `127.0.0.1:8080`. On first launch it creates:

```text
~/.reedpipe/ReedPipeRootCA.pem
~/.reedpipe/ReedPipeRootCA.key.pem
```

Terminal 2 — serve the repository root:

```bash
python3 -m http.server 8000
```

Open [http://localhost:8000/Public/index.html](http://localhost:8000/Public/index.html)
and wait for the green `Connected — live` status.

### 4. Generate traffic

Plain HTTP:

```bash
curl -x http://127.0.0.1:8080 http://example.com
```

HTTPS, trusting the ReedPipe CA for this command only:

```bash
curl \
  -x http://127.0.0.1:8080 \
  --cacert ~/.reedpipe/ReedPipeRootCA.pem \
  https://example.com
```

Run the complete smoke test:

```bash
./Scripts/generate-test-traffic.sh
```

The script sends 20 requests: 10 HTTP and 10 HTTPS using GET, POST, PATCH, and
DELETE. It includes JSON bodies, one intentional connection failure, and one
intentional HTTP 503 response. A normal summary is:

```text
18 passed, 2 expected error responses, 0 unexpected failures, 20 total.
```

The test uses public endpoints, so temporary network or service issues can
produce an unexpected result.

## Using the monitor

Each completed exchange appears as a row containing:

- Method
- URL
- Status or upstream error
- Duration in milliseconds
- Response action

Click `View` in the Response column to open the captured HTTP version, status
line, headers, and body. The dialog shows Base64 when a body is not valid
UTF-8. Requests that fail before receiving an upstream response show their
error in the Status column and `Unavailable` in the Response column.

HTTPS entries contain the decrypted application-level HTTP response, not the
encrypted TLS record bytes.

## Routing a browser through ReedPipe

A browser must use the proxy and trust `ReedPipeRootCA.pem` to inspect HTTPS.
For Firefox:

1. Open `about:preferences#privacy`, then **Certificates** → **View
   Certificates...** → **Authorities** → **Import...**.
2. Select `~/.reedpipe/ReedPipeRootCA.pem` and trust it to identify websites.
3. Open `about:preferences#general`, then **Network Settings** → **Settings...**.
4. Choose **Manual proxy configuration**, set HTTP Proxy to `127.0.0.1` and
   port `8080`, and enable **Also use this proxy for HTTPS**.

Restore the browser's normal proxy configuration when finished.

## Bypassing HTTPS interception

Clients using certificate pinning, mutual TLS, or another incompatible TLS
policy can use a raw tunnel. Bypassed traffic is forwarded but cannot be
inspected or displayed.

Provide a comma-separated host list when starting the proxy:

```bash
REEDPIPE_BYPASS_HOSTS=example.com,api.example.com swift run Proxy
```

Alternatively, add one exact hostname per line to:

```text
~/.reedpipe/bypass.txt
```

The bypass list is loaded when the proxy starts; restart it after changing the
environment variable or file. Matching is exact and does not currently support
wildcards.

## Smoke-test configuration

The traffic script supports these environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `REEDPIPE_PROXY_URL` | `http://127.0.0.1:8080` | Proxy address |
| `REEDPIPE_CA_CERTIFICATE` | `~/.reedpipe/ReedPipeRootCA.pem` | CA used by HTTPS requests |
| `REEDPIPE_CONNECT_TIMEOUT` | `5` | curl connection timeout in seconds |
| `REEDPIPE_REQUEST_TIMEOUT` | `20` | curl total timeout in seconds |

Example:

```bash
REEDPIPE_REQUEST_TIMEOUT=30 ./Scripts/generate-test-traffic.sh
```

## What to rebuild

| Changed files | Required action |
| --- | --- |
| `Sources/Proxy/` | Rebuild and restart `Proxy` |
| `Sources/Core/` | Rebuild/restart `Proxy` and repackage `Frontend` |
| `Sources/Frontend/` | Repackage `Frontend`, then hard-refresh the browser |
| `Public/index.html` | Hard-refresh the browser; no Swift rebuild |
| `Scripts/` or `README.md` | No build |

Repackage the frontend with:

```bash
swift package \
  --scratch-path .build/wasm \
  --swift-sdk "$WASM_SDK" \
  js --use-cdn --product Frontend
```

## Troubleshooting

### `index.js` returns 404

Run the frontend packaging command from the repository root and serve that
same root with `python3 -m http.server 8000`. The expected bundle is
`.build/wasm/plugins/PackageToJS/outputs/Package/index.js`.

### The page stays disconnected

Confirm `swift run Proxy` is still running and listening on `127.0.0.1:8080`.
The frontend reconnects automatically with exponential backoff.

### The table stays empty

Wait for `Connected — live` before generating traffic. ReedPipe does not replay
older exchanges. Also confirm the test client is explicitly using the proxy.

### HTTPS certificate verification fails

Use `--cacert ~/.reedpipe/ReedPipeRootCA.pem` with curl or import that
certificate into the client's trust store. Also confirm the system clock is
correct. You do not need to share or install the private key.

### Port 8080 is already in use

Stop the older ReedPipe process before starting a new build. The proxy address
is currently fixed to `127.0.0.1:8080`.

## Known limitations

- HTTP/1.1 is supported; HTTP/2 and HTTP/3 are not.
- Requests and responses are fully buffered in memory, so large downloads,
  uploads, and streaming responses are not suitable.
- Connections are closed after each captured exchange; keep-alive and multiple
  requests per HTTPS tunnel are not currently supported.
- The monitor is in-memory and live-only, with no persistence, search, export,
  or replay.
- Certificate-pinned and mutual-TLS clients may reject interception; use the
  bypass list when inspection is not required.
- The proxy uses one in-memory leaf certificate whose Subject Alternative Name
  list grows as new HTTPS hosts are visited during the process lifetime.
- IPv6 literal `CONNECT` targets are not parsed correctly.
- The proxy and WebSocket feed bind to localhost with fixed ports and do not
  provide authentication or remote access.

## Security

`~/.reedpipe/ReedPipeRootCA.key.pem` can sign certificates for any hostname.
Never share it. Trusting `ReedPipeRootCA.pem` gives ReedPipe permission to
intercept HTTPS traffic on that client, so remove that trust when it is no
longer needed.

## Tests

Run the Core model, encoding, formatting, and JSON round-trip tests:

```bash
swift test --filter CoreTests
```

Validate the traffic script without sending requests:

```bash
bash -n Scripts/generate-test-traffic.sh
```

## License

ReedPipe is available under the MIT License. See [LICENSE](LICENSE).

## Acknowledgements

This project was created during the official
[Swift Mentorship Program](https://www.swift.org/mentorship/).
