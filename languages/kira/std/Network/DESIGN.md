# Kira Network: design

Status: design of record, 2026-10-14. It covers every network need Kira programs
have for the next six months: Harmony's client and server, the model gateway,
tunnels, realtime sync, and whatever Kite apps need. A layer this document does
not name is out of scope until it is added here first.

## 1. Goals

1. **Modern first.** HTTP/3 over QUIC is the primary transport. TLS 1.3 is the
   only TLS. Every stream is multiplexed, and bidirectional streams are a public
   primitive, not something hidden inside HTTP.
2. **Protocols are Kira.** TLS 1.3, QUIC, HTTP/3, QPACK, HTTP/2, HPACK,
   HTTP/1.1, WebTransport, WebSocket, Server-Sent Events and the DNS message
   codec are written in Kira, in the `Network` library. The kernel gives only
   what Kira cannot reach without the OS, plus vetted cryptography (section 3).
3. **One HTTP model.** A request, a response, a header field and a body are the
   same values on HTTP/1.1, HTTP/2 and HTTP/3 (RFC 9110). Version is a property
   of a connection, never of the code that sends a request.
4. **Sans-I/O cores.** Every protocol engine is a state machine that takes bytes
   and time in and gives bytes, timers and events out. No engine owns a socket,
   reads a clock or blocks. One driver does I/O for all of them. That is what
   makes the engines testable byte-for-byte, and what lets one driver serve a
   UI frame loop, a server loop and a background thread with the same code.
5. **No hidden waits.** Kira has no coroutines (KIR D-019) and tasks are
   cooperative. The library never parks a thread behind the caller's back: a
   caller either asks for what is ready now, or says how long it is willing to
   wait.

Non-goals for this period: TLS 1.2 and older, HTTP/1.0 keep-alive quirks,
proxies other than HTTP CONNECT, FTP, SMTP, raw IP, multicast, mDNS, and QUIC
multipath.

## 2. Layers

```
 Harmony, Kite apps, the gateway
 ─────────────────────────────────────────────────────────────── Network (Kira)
  HttpClient · HttpServer · WebTransport · WebSocket · EventStream   API
  HTTP semantics: Request, Response, Fields, Method, Status, Body    model
  Http3 + Qpack │ Http2 + Hpack │ Http1                              framing
  Driver: sockets, timers, DNS, connection pool, Alt-Svc             I/O
 ─────────────────────────────────────────────────────────────── Foundation
  QuicNode: QUIC streams for a program's own protocol                API
  Quic (transport, recovery, congestion)  │  TlsStream (records)     transport
  Tls13 handshake engine + key schedule                              security
  Wire: WireReader, WireWriter, varints                              wire
  Socket, Poller, Resolver, Crypto wrappers over kernel services
 ─────────────────────────────────────────────────────────────── KLF kernel
  klf.net (sockets, poller, resolver)   klf.crypto (primitives, X.509)
```

`Network` is a bundled library under `std/`: `import Network` resolves it by name
from the installed std, and no manifest lists it. The sysroot unit compiles
only Foundation and the packages it reaches by path (Heap); `Network` is built
as its own unit by each program that imports it, so its private declarations
and Foundation's never meet in one unit. Its own tests are cases in
`app/Tests/`, run by `kira test std/Network`. Kernel services are Foundation's
alone, so Foundation holds the thin, typed wrappers over `klf.net` and
`klf.crypto`, and `Network` builds everything else on them.

QUIC, TLS 1.3 and the wire codec are Foundation's too, under
`std/Foundation/app/net/quic/`, `net/tls/` and `Wire.kira`, so a package that speaks
its own protocol over QUIC streams depends on Foundation alone. Their names
carry a `Quic`, `Tls` or `Wire` prefix, since every Foundation name is in
every unit's scope. `QuicNode` (`Quic/Node.kira`) is their driver: one value
that owns a poller and UDP sockets, listens and dials, and gives connection
and stream events from `wait` and `poll`, as this library's driver does for
HTTP. `quicTestIdentity()` and `quicTestAnchors()` give the test PKI to any
package's tests.

## 3. What the kernel provides, and why only that

The kernel provides two things.

- **OS access:** sockets, readiness, name resolution. Kira reaches the OS only
  through services (framework D-382 and the rule against system calls outside
  Tessera).
- **Cryptographic primitives and certificate path validation:** constant-time
  arithmetic and X.509 chain building are the two places where a subtle bug is
  a silent, remote, total break. They come from `ring` and `rustls-webpki`,
  which are audited. Everything built from them, including the TLS 1.3
  handshake, the key schedule and QUIC packet protection, is Kira.

Secret material that never needs to be read by Kira stays in the kernel behind
a handle: ephemeral key-agreement private keys and long-term signing keys.
Traffic secrets are derived in Kira, because the key schedule is Kira; they are
`[UN8]` held by the engine that owns them.

### 3.1 `klf.net`

Services follow section 8.12: integers and (pointer, length) pairs, coarse
calls, a negative failure word on failure. Handles are positive words, one
table per process, shared by the VM and the native runtime (crate
`klf-host-net`, as `klf-host-files` does for `klf.fs`).

| Service | Signature | Answer |
| --- | --- | --- |
| `klf.net.udp_bind` | `(address ptr, len) -> i64` | socket handle |
| `klf.net.udp_send` | `(socket, peer ptr, len, bytes ptr, len) -> i64` | bytes sent |
| `klf.net.udp_receive` | `(socket, bytes ptr, cap, peer ptr, cap) -> i64` | bytes received, peer written as text |
| `klf.net.tcp_connect` | `(address ptr, len) -> i64` | stream handle; connecting continues in the background |
| `klf.net.tcp_listen` | `(address ptr, len, backlog) -> i64` | listener handle |
| `klf.net.tcp_accept` | `(listener, peer ptr, cap) -> i64` | stream handle, or would-block |
| `klf.net.tcp_send` | `(stream, bytes ptr, len) -> i64` | bytes accepted |
| `klf.net.tcp_receive` | `(stream, bytes ptr, cap) -> i64` | bytes read; 0 is the peer's end |
| `klf.net.tcp_shutdown` | `(stream) -> i64` | 1 when the write side is closed |
| `klf.net.local_address` | `(handle, text ptr, cap) -> i64` | length of the bound address |
| `klf.net.close` | `(handle) -> i64` | 1 when closed |
| `klf.net.poller_create` | `() -> i64` | poller handle |
| `klf.net.poller_watch` | `(poller, handle, interest, token) -> i64` | 1 when registered |
| `klf.net.poller_wait` | `(poller, timeout ns, events ptr, cap) -> i64` | event count |
| `klf.net.poller_wake` | `(poller) -> i64` | 1; callable from any thread |
| `klf.net.resolve` | `(poller, host ptr, len, token) -> i64` | lookup handle; completes as a poller event |
| `klf.net.resolved` | `(lookup, text ptr, cap) -> i64` | length of the address list |

Addresses cross as text (`192.0.2.1:443`, `[2001:db8::1]:443`): parsing is a
Kira concern, and text is what every language's FFI already passes. An address
a service writes back is NUL-ended text, written only when it fits, as
`klf.fs.list` writes names. All sockets are non-blocking, and readiness is
reported when it changes: a caller reads or writes until it is told
would-block before it waits again. Interest and event words are bit sets:
readable 1, writable 2, peer closed 4, error 8, resolved 16, woken 32. An event
is two `i64` words in the destination: the token, then the bits; a wake is the
event with token 0. A wait's timeout is in nanoseconds, negative to wait
until an event and 0 to take only what is ready. `resolve` takes a host name
without a port, and `resolved` answers its addresses, each NUL-ended and
without a port, or would-block while the lookup runs.

Failure words: -1 would block, -2 refused, -3 unreachable, -4 address in use,
-5 invalid handle, -6 invalid address, -7 timed out, -8 reset, -9 not found
(resolution), -10 any other I/O failure.

The resolver runs the platform's own resolver (getaddrinfo, or its equivalent)
on a kernel worker thread, so a lookup never blocks the poller. Encrypted DNS
and HTTPS records (section 9) are Kira on top of UDP and HTTP.

### 3.2 `klf.crypto`

On `ring` and `rustls-webpki` (framework D-385).

| Service | Purpose |
| --- | --- |
| `klf.crypto.random` | Fill a buffer from the OS CSPRNG |
| `klf.crypto.digest` | SHA-256 or SHA-384 of a buffer |
| `klf.crypto.hmac` | HMAC-SHA-256/384 |
| `klf.crypto.hkdf_extract`, `hkdf_expand` | RFC 5869; the extracted key crosses as bytes |
| `klf.crypto.aead_seal`, `aead_open` | AES-128-GCM, AES-256-GCM, ChaCha20-Poly1305, in place, with associated data |
| `klf.crypto.header_mask` | QUIC header-protection mask (AES-ECB or ChaCha20, RFC 9001 section 5.4) |
| `klf.crypto.agreement_create` | X25519 or P-256 ephemeral key pair; answers a handle and writes the public key |
| `klf.crypto.agreement_finish` | Peer public key in, shared secret out; releases the handle |
| `klf.crypto.verify` | Verify a signature by the key of a DER certificate: ECDSA P-256/P-384, RSA-PSS SHA-256/384, Ed25519 |
| `klf.crypto.key_load` | Load a PKCS#8 DER private key; answers a signing-key handle. PEM is decoded in Kira |
| `klf.crypto.sign` | Sign with a key handle under a named scheme |
| `klf.crypto.certificate_verify` | Verify a certificate list for a server name at a time, against the bundled Mozilla roots plus anchors the caller passes |
| `klf.crypto.release` | Release a key handle |

Algorithms and schemes cross as the TLS registry code points (for example
`0x0403` for `ecdsa_secp256r1_sha256`, `0x001d` for `x25519`, `0x1301` for
`TLS_AES_128_GCM_SHA256`, and 4 and 5 for SHA-256 and SHA-384), which Kira
declares as `@Open` enums. A code point is the wire's own name for the
algorithm, so no second numbering is invented. A certificate list crosses as a
TLS Certificate message holds it: each DER certificate behind a 24-bit length,
end entity first. The caller passes the time, from `klf.time.wall`.

Failure words: -1 unsupported, -2 invalid input, -3 rejected (a tag or a
signature that does not verify), -4 invalid handle, -5 destination too small,
-6 unknown issuer, -7 expired or not yet valid, -8 wrong name, -9 any other bad
certificate. The TLS engine maps each to its alert (RFC 8446 section 6.2).

Not yet: the platform's own trust store. Until it lands, a program that must
trust a private CA passes it as an anchor.

## 4. Bytes

Every engine reads and writes `[UN8]`. `UN8` is stored as one byte (decision
of 2026-10-14, framework section 21.1), so an array of them is a byte buffer
that a service reads in place, with no copy.

- `WireReader` reads big-endian integers, QUIC variable-length integers
  (RFC 9000 section 16), length-prefixed vectors (TLS's 8-, 16- and 24-bit
  prefixes) and slices. Every read answers `Result<Value, WireFailure>`, so a
  truncated or malformed message is a failure value, never a trap.
- `WireWriter` mirrors it, with `reserveLength(prefix)` and `fillLength(mark)`
  for vectors whose size is known only once written.
- Peer bytes are untrusted. Every decoder checks every length against what
  remains before reading it, and bounds every allocation by a limit the engine
  declares (`QuicLimits`, `HttpLimits`).

## 5. Security: TLS 1.3 (`Tls13`)

One sans-I/O engine, `TlsHandshake`, in two roles (`.Client`, `.Server`) and two
carriers:

- **QUIC carrier:** handshake messages travel in CRYPTO frames at the Initial,
  Handshake and 1-RTT levels; the engine emits `(EncryptionLevel, [UN8])` and
  `Secrets(level, client, server)` events (RFC 9001 section 4). The transport
  parameters extension carries QUIC's parameters.
- **Record carrier:** `TlsStream` wraps the engine with the TLS 1.3 record
  layer (RFC 8446 section 5) for TCP: HTTP/2 and HTTP/1.1 over TLS.

Supported: cipher suites `TLS_AES_128_GCM_SHA256`, `TLS_AES_256_GCM_SHA384`,
`TLS_CHACHA20_POLY1305_SHA256`; groups X25519 and secp256r1; signature schemes
ECDSA P-256/P-384, RSA-PSS and Ed25519; ALPN; SNI; HelloRetryRequest; key
update. Certificates are verified through `klf.crypto.certificate_verify`, and
then CertificateVerify is checked against the end-entity key; the handshake
fails closed on any error. The server role signs with a key handle.

Later in this period: session tickets, PSK resumption and 0-RTT (replay-safe
methods only), ECH. Never: TLS 1.2, renegotiation, compression, RSA key
exchange.

## 6. Transport: QUIC (`Quic`)

QUIC version 1 (RFC 9000, 9001, 9002), with version 2 (RFC 9369) and DATAGRAM
(RFC 9221) in the same engine.

- `QuicEndpoint` owns one UDP socket's worth of connections: it routes datagrams
  by destination connection ID, answers version negotiation, sends stateless
  resets, and validates new clients with Retry when it is under load.
- `QuicConnection` is the sans-I/O core:
  - `receive(datagram, from, now)` feeds bytes in;
  - `transmit(now) -> Datagram?` gives the next datagram to send;
  - `deadline() -> Instant?` says when it next needs `expire(now)`;
  - `event() -> QuicEvent?` drains what happened (handshake done, stream
    readable, stream writable, stream opened by the peer, datagram, closed).
- Packet number spaces, ACK generation with ACK delay, loss detection and the
  probe timeout follow RFC 9002 exactly. Congestion control is a trait,
  `CongestionController`, with NewReno (RFC 9002 section 7) first and CUBIC
  (RFC 9438) next; pacing is part of the transmit decision.
- Streams: `StreamId` is `distinct`; the two low bits become a
  `StreamKind { .Bidirectional .Unidirectional }` and an initiator, decoded
  once. Each stream has send and receive state machines (RFC 9000 section 3),
  per-stream and connection flow control with automatic window growth, and
  `STOP_SENDING` and `RESET_STREAM` as typed results.
- Connection IDs: issued and retired per `NEW_CONNECTION_ID` /
  `RETIRE_CONNECTION_ID`; path validation for migration comes after the first
  release, as does ECN.
- Limits are explicit: `QuicLimits` holds stream counts, window sizes, idle
  timeout and the maximum UDP payload, with defaults declared once.

## 7. HTTP

### 7.1 The model

```kira
@Open enum Method: Number { ... }       // GET HEAD POST PUT DELETE CONNECT OPTIONS PATCH, plus any token
@Open enum Status: Number { Ok = 200  NoContent = 204  ... }
struct Field { let name: String  let value: String }      // name lowercased once, at decode
struct Fields { var entries: [Field] }                     // ordered, repeatable
struct Request {
    let method: Method
    let target: Target                                     // scheme, authority, path and query
    var fields: Fields
    var body: Body
}
struct Response { let status: Status  var fields: Fields  var body: Body }
enum Body { Empty  Bytes([UN8])  Streaming(BodyStream) }
```

The protocol, `.Http1` `.Http2` `.Http3`, is a property of the `Connection`.
Pseudo-header fields (`:method`, `:path`, ...) never appear in `Fields`: the
HTTP/2 and HTTP/3 codecs map them to the typed members.

### 7.2 HTTP/3 (`Http3`, `Qpack`)

RFC 9114 over the QUIC engine: the control stream and SETTINGS, request
streams with HEADERS and DATA frames, GOAWAY, unknown frame and stream types
ignored as the RFC requires, and the extended CONNECT protocol (RFC 9220).

QPACK (RFC 9204): static table and Huffman coding. The first release
advertises a dynamic table capacity of 0 and blocked streams 0, which every
peer must accept; a dynamic table encoder and decoder come later in the period.

### 7.3 HTTP/2 (`Http2`, `Hpack`)

RFC 9113 over `TlsStream` with ALPN `h2`: the frame layer, stream states,
flow control, SETTINGS, PING, GOAWAY, and HPACK (RFC 7541) with its dynamic
table. It is for origins that do not offer HTTP/3.

### 7.4 HTTP/1.1 (`Http1`)

RFC 9112: request and status lines, chunked transfer coding, persistent
connections without pipelining, `Upgrade` for WebSocket. It is for cleartext
loopback services (a local model proxy) and origins that offer nothing newer.

### 7.5 Choosing a protocol

The client keeps an `AltServiceCache` (RFC 7838) and, later, HTTPS DNS records
(RFC 9460):

1. A known `h3` alternative: connect over QUIC, and in parallel start TCP after
   a short head start (Happy Eyeballs, RFC 8305); the first to finish its
   handshake wins, and the loser is closed.
2. Otherwise, TCP with TLS and ALPN `h2, http/1.1`. An `Alt-Svc: h3` answer is
   remembered for next time.
3. `http://` is HTTP/1.1, and is only allowed to loopback addresses unless the
   request explicitly opts in through `Transport.Cleartext`.

A request can pin a protocol (`Transport.Http3Only`) for tests and for
endpoints known to be QUIC-only.

## 8. The public API

### 8.1 The driver and waiting

```kira
var network = try openNetwork(NetworkOptions {})
```

`Network` owns the poller, the sockets, every engine and the connection pool.
It is a value the program owns and passes as `borrow mut`; there is no global
network state. Three ways to move it:

- `network.wait(until: deadline) -> [NetworkEvent]` blocks the calling thread
  until something happens or the deadline passes. Server loops and command-line
  tools use it.
- `network.poll() -> [NetworkEvent]` never blocks. A UI frame loop calls it
  once per frame.
- `network.wake()` interrupts a `wait` from another thread, once `klf.thread`
  exists, so a background-thread network and a UI thread can share work
  through channels.

Every operation that can take time returns an ID at once, and its progress
arrives as events. Convenience calls that wait for one outcome (`fetch`) are
written on `wait` and say so in their names and signatures: they take a
deadline.

```kira
enum NetworkEvent {
    ResponseHead(ResponseHead)              // the request's ID, status, fields, protocol
    ResponseBody(BodyChunk)                 // the request's ID and bytes
    ResponseEnded(RequestEnd)               // trailers, or the failure that ended it
    Incoming(IncomingRequest)               // server side
    SessionOpened(SessionId)                // WebTransport and WebSocket
    StreamOpened(SessionStream)             // a peer's new stream in a session
    StreamData(SessionBytes)
    StreamEnded(StreamEnd)                  // finished, reset or stopped
    Datagram(SessionDatagram)
    SessionDraining(SessionId)              // WT_DRAIN_SESSION: wind down soon
    SessionClosed(SessionClose)
}
```

### 8.2 Client

```kira
let target = try targetOf("https://api.anthropic.com/v1/messages") otherwise return .Error(.Url)
let request = Request { method: .Post, target: target, fields: fields, body: .Bytes(body) }
let id = try network.send(request) otherwise return .Error(.Network)
while true {
    for event in network.wait(until: deadline) {
        match event {
            ResponseBody(chunk) -> stream.feed(chunk.bytes)
            ...
        }
    }
}
```

`targetOf(url)` reads an absolute `http` or `https` URL into a `Target`,
refusing userinfo and dropping the fragment. A request that names no
`user-agent` gets `NetworkOptions.userAgent` (RFC 9110 section 10.1.5), since
some origins refuse one without it.

`network.fetch(request, until: deadline) -> Result<Response, HttpFailure>`
collects a whole response. `EventStream` decodes `text/event-stream` (the
WHATWG grammar) from body chunks into `ServerEvent { name, data, id, retry }`,
which is how every model provider streams.

`HttpFailure` is specific: `.Resolve(Host)`, `.Connect(ConnectFailure)`,
`.Tls(TlsAlert)`, `.Protocol(ProtocolError)`, `.Reset(StreamReset)`,
`.TimedOut(Phase)`, `.TooLarge(Limit)`, `.Closed`.

### 8.3 Server

```kira
var server = try network.serve(ServeOptions {
    address: "[::]:4433",
    identity: try Identity.load(certificatePath, keyPath) otherwise return .Error(.Identity),
    protocols: [.Http3, .Http2, .Http1]
})
```

One address serves QUIC on UDP and TLS on TCP, and every TCP response
advertises `Alt-Svc: h3`. Requests arrive as `Incoming` events; the program
answers with `network.respond(id, head)`, `network.write(id, bytes)` and
`network.finish(id, trailers)`. Routing, middleware and Kten encoding belong to
the program or a framework above `Network`, never to `Network` itself.

### 8.4 Bidirectional streams and multiplexing

Multiplexing is the default everywhere: many requests share one QUIC or HTTP/2
connection, with per-stream flow control, so a long model stream never holds
up a short request.

For realtime work, a **session** is the public bidirectional primitive:

- **WebTransport over HTTP/3** (draft-ietf-webtrans-http3, with the capsule
  protocol of RFC 9297): `network.openSession(target, fields)` gives a
  `SessionId`. A server sees the extended CONNECT as `Incoming` with
  `protocolName` `"webtransport-h3"` and takes it with
  `network.acceptSession(request, fields)`, or refuses it with an ordinary
  response. In a session either side opens bidirectional or unidirectional
  streams (`openStream(session, .Bidirectional)`), writes them with
  `writeStream`, ends them with `resetStream` or `stopStream`, sends
  unreliable datagrams with `sendDatagram`, and ends the session with
  `closeSession(session, error, reason)`. Streams are independent, so one
  blocked stream never stalls another. No WebTransport flow control is
  announced, so a connection carries one session at a time (draft section
  5.1); a stream reset uses QUIC's RESET_STREAM_AT so the session header
  still arrives.
- **WebSocket** (RFC 6455 over HTTP/1.1, RFC 8441 over HTTP/2, RFC 9220 over
  HTTP/3): one ordered message stream, for peers that speak nothing else.
- **Raw QUIC** with an application ALPN, for Kira-to-Kira protocols such as
  Harmony's tunnel: `network.connectQuic(address, alpn)`, and the same stream
  and datagram calls.

Harmony's realtime sync uses one WebTransport session per device: a control
stream for commands and acknowledgements, one stream per subscription, and
datagrams only for presence-like data that may be lost.

### 8.5 Observability

`NetworkOptions.tap: Tap?` receives every HTTP exchange's wire record before
decoding: URL, protocol, request head and body, status, response head and raw
body bytes. Header values the request marked sensitive (`Field.sensitive`) are
replaced by their name, so a key is never recorded. Connection-level metrics
(RTT, congestion window, lost packets, bytes) are readable per connection, and
`qlog` output (draft-ietf-quic-qlog) is an option for debugging QUIC.

## 9. DNS

The first release uses `klf.net.resolve`. Later in this period, `Network`
adds the DNS message codec (RFC 1035, RFC 9460 SVCB/HTTPS records) and
DNS-over-HTTPS (RFC 8484) through its own client, so h3 can be discovered
before the first request.

## 10. Concurrency and threads

Until the runtime has threads (`klf.thread`, framework section 18.9), a
program holds one `Network`, on the thread that runs it. Once it has them:

- a `Network` stays single-owner: it is moved to a thread, never shared;
- other threads talk to it through `Channel`s and call `network.wake()` after
  sending, which is the one operation safe to call from any thread;
- a UI application runs its `Network` on a background thread and posts results
  to the main thread with `MainThread.post`.

Nothing in the API changes when that happens: events in, commands out.

## 11. Testing

- Each engine is tested sans-I/O: byte vectors from the RFCs (RFC 9001
  appendix A's packet protection samples, RFC 8448's TLS 1.3 traces, RFC 7541
  and RFC 9204 examples) run through it without a socket.
- Two engines talk to each other in memory: a client `QuicConnection` and a
  server one exchanging datagrams through a lossy, reordering in-memory link,
  with a virtual clock.
- Interop runs against real servers (Cloudflare, Google, a model provider) by
  hand, never in the default test run.

## 12. Phases

| Phase | Contents |
| --- | --- |
| 1, now | `UN8` stored as one byte; `klf.net` and `klf.crypto`; `Bytes`; TLS 1.3 client and server; QUIC v1 with NewReno; HTTP/3 with static QPACK; `Network` driver, client and server; HTTP/1.1 over TCP and TLS; `EventStream`; WebTransport sessions |
| 2 | HTTP/2 and HPACK; Alt-Svc and Happy Eyeballs racing; connection pool limits and idle reuse; CUBIC; session resumption |
| 3 | WebSocket on all three versions; QPACK dynamic table; DNS codec, HTTPS records and DoH; QUIC v2, ECN, connection migration; qlog |
| 4 | 0-RTT; ECH; GSO and GRO batching in the kernel |

Every phase ships complete: a phase adds layers, it never leaves a layer half
written.
