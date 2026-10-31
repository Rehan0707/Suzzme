# Watched Links: transport boundary and evidence

Status reviewed on 22 October 2026. **Production fetching remains disabled.**
The remaining blocker is proof that a DNS result contains the complete initial
A/AAAA answer set, including every unsafe/mixed answer. DNS-SD's `MoreComing`
flag closes a delivered callback batch; it does not certify that complete set.
The local package is wired into the app, so ordinary app builds type-check the
real adapter. Availability still requires the explicit
`SUZZME_PINNED_WATCHED_TRANSPORT` compilation condition, which the app project does
not enable; a runtime guard rejects requests before the adapter calls the client.
An isolated package connection test is not an installed-app, physical-device, or
distribution acceptance result.

This note covers user-configured Watched Links only. It grants no Safari tab
monitoring, browser pairing, provider-account access, broad web crawling, or
authority to execute instructions found in a page. The approved logo is outside
this change.

## End-to-end authority

| Stage | Production boundary |
| --- | --- |
| Consent | [`WatchedLinksView.swift`](Suzzme/Features/Sources/WatchedLinksView.swift) presents per-page review before resuming a saved link. Adding a page explicitly reviews anonymous public-page checking. [`WatchedLinkRecord.permitsFetching`](Suzzme/Core/Information/WatchedLinks/WatchedLinkModels.swift) requires both `enabled` and the current transport-consent revision. Missing or unknown revisions do not resume checking. |
| URL | [`WebURLPolicy.swift`](Suzzme/Core/Information/WatchedLinks/WebURLPolicy.swift) accepts canonical HTTPS DNS identities, removes fragments/default port, and rejects credentials, unusual/encoded numeric authorities, local names, literal-IP URLs, other ports, unsafe privacy classifications, and URLs over 2,048 UTF-8 bytes. A stored URL must equal its newly validated canonical form before a fetch starts. |
| DNS | Two native `DNSServiceQueryRecord` operations request A and AAAA with intermediates enabled. A private serial queue owns callbacks, deadlines and deallocation; completion terminates both queries before resuming, while DNS-SD drains descriptor cleanup asynchronously. CNAME/unknown records, changed callback names, removals, malformed addresses and inconsistent family callbacks fail closed. **Complete-initial-answer-set proof is still missing:** a delivered batch is not an authoritative full RRset. Native lifetime checks passed; they do not close this semantic gap. |
| Address policy | `approvedAddresses` validates every address supplied in the resolver result before selecting a numeric endpoint; this does not prove that result is complete. Empty, ambiguous, over-limit, or mixed public/unsafe results fail closed. IPv4 special-use ranges and a conservative allocated IPv6-unicast snapshot are excluded/allowed explicitly; future IPv6 allocations require review. The package repeats a numeric-address policy at its public API boundary. |
| TCP | [`PinnedHTTPClient.swift`](Packages/SuzzmeWatchedTransport/Sources/SuzzmeWatchedTransport/PinnedHTTPClient.swift) constructs `SocketAddress(ipAddress:port:)` and calls NIO `ClientBootstrap.connect(to:)` with that value. No hostname is given to the socket bootstrap, no second lookup selects the destination, and no HTTP connection pool can substitute an older connection. |
| Peer identity | The first inbound handler, `PeerGate`, compares the connected channel's remote address and port against the exact selected socket address before forwarding `channelActive` to TLS. The pinned NIO implementation populates that remote-address cache using the socket's `getpeername` path after connect and before firing activation; it is not merely the requested destination echoed by app code. |
| TLS | NIOSSL receives the original canonical DNS hostname as `serverHostname`, with TLS 1.2 minimum and HTTP/1.1 ALPN. [`OfflineServerTrust.swift`](Packages/SuzzmeWatchedTransport/Sources/SuzzmeWatchedTransport/OfflineServerTrust.swift) verifies the received certificate chain using `SecPolicyCreateSSL(true, hostname)` and normal system trust through `SecTrustEvaluateWithError`. Production has no alternate anchor or accept-invalid-certificate option. `SecTrustSetNetworkFetchAllowed(false)` prevents trust evaluation from opening AIA/OCSP connections outside the pinned transport. SNI is not treated as certificate validation. |
| HTTP | After successful TLS, the client sends one GET with the original DNS `Host`, supported text MIME preferences, `Accept-Encoding: identity`, and `Connection: close`. Only bounded ETag/Last-Modified validators may be added. There is no request body, cookie jar, authorization header, browser session, referrer, model prompt, page content, HTTP proxy/CONNECT, SOCKS, or PAC implementation. |
| Redirects | [`BoundedWatchedLinkFetcher`](Suzzme/Core/Information/WatchedLinks/WatchedWebSource.swift) receives one-hop status/headers, then validates each redirect URL, resolves its destination, rechecks every address, and creates another pinned connection. It tracks visited canonical URLs, permits at most three redirects, and rejects HTTP downgrades and malformed locations. Validators are retired after **every** redirect, including same-origin redirects. No credentials exist to forward. |
| Parsing | Maintained NIO HTTP parsing handles the response. Budgets run before the HTTP decoder and around body collection. Ambiguous duplicate critical fields, unsupported transfer/content encodings, malformed lengths, unsupported MIME, interim responses and protocol upgrades fail closed. `Set-Cookie` is discarded. A redirect/error response is returned after its bounded head without collecting its body. |
| Extraction | [`WebContentExtractor.swift`](Suzzme/Core/Information/WatchedLinks/WebContentExtractor.swift) reads only bounded UTF-8/Latin-1 bytes. Its forward text tokenizer strips tags, respects quoted attributes/comments, suppresses head/script/style/noscript/SVG/navigation/footer/aside content, and fails closed on unfinished or ambiguous markup. It neither executes JavaScript nor loads subresources, follows meta refresh, resolves entities from a DTD, or creates a browser. Cancellation is checked periodically during scanning and semantic extraction. Privacy classification covers visible text before the retained text prefix is taken. |
| Persistence | [`WatchedLinkStore.swift`](Suzzme/Core/Information/WatchedLinks/WatchedLinkStore.swift) commits only the current refresh generation for a currently consented link. Disable, remove, reset and superseding refreshes retire older ownership; late callbacks cannot resurrect records. Stored state contains bounded extracted details, fingerprints and validators, not raw HTML. Change history expires after 30 days. Failed refreshes back off and do not turn old details into a new success. |
| Daily Summary | [`WatchedWebInformationSource`](Suzzme/Core/Information/WatchedLinks/WatchedWebSource.swift) permits an observation only while transport is available, its exact page remains consented, the page is successfully checked and fresh, and the change still exists. [`ProactiveIntelligenceEngine.swift`](Suzzme/Core/Proactive/ProactiveIntelligenceEngine.swift) revalidates cached watched references by exact external identity **and fingerprint**, covering the briefing, time-critical items, context and opportunities. Legacy artifacts with incomplete provenance are withheld without rewriting their saved JSON. Page text cannot grant action, settings, or Personal Memory authority. |

The NIO peer-name path was inspected in the resolved, exact-version source:
`NIOPosix/BaseSocketChannel.finishConnect` →
`updateCachedAddressesFromSocket` → `remoteAddress0` →
`BaseSocket.remoteAddress` → `NIOBSDSocket.getpeername`, before
`pipeline.fireChannelActive`. Immediate-connect completion also updates the
address cache before activation. The dependencies are pinned to swift-nio
2.104.0 and swift-nio-ssl 2.37.5 in
[`Package.swift`](Packages/SuzzmeWatchedTransport/Package.swift).

## DNS implementation and remaining acceptance blocker

The resolver now uses independently owned native A/AAAA queries rather than
`getaddrinfo` workers. Callback processing, terminal state, timer cancellation and
`DNSServiceRefDeallocate` share one private serial queue. Cancellation/timeout
terminates both owned queries before completing the awaiting task. DNS-SD's
cancelled dispatch-source descriptors drain after the current callback unwinds;
the native fixture observed all six descriptors closed 1.76–2.09 milliseconds
after deallocation. Production neither polls nor directly closes those owned
DNS-SD descriptors. A small positive
test compilation guard provides scripted callbacks and local-only query options;
normal production initialization exposes neither override. The focused resolver
suite passed 65 checks, including actual LocalOnly daemon operations for negative
A/AAAA completion, pending-query timeout and cancellation. Forty scripted
success/cancellation races are separate evidence, not actual public DNS queries.

Each family is marked finished when its delivered batch ends or it reports
`NoSuchRecord`. The SDK's `MoreComing` semantics do **not** prove that those two
batches contain every initial A/AAAA answer. A later unsafe address could be
delivered after that apparent boundary. This prevents satisfying the user's
strict mixed-answer rejection contract even though the selected socket itself
is pinned and all addresses actually received are checked. A quiet interval or
a mock that promises complete batches would not close this proof gap.

Apple's [open-source DNS-SD client implementation](https://github.com/apple-oss-distributions/mDNSResponder/blob/main/mDNSShared/dnssd_clientstub.c#L1300)
sets `MoreComing` by checking for more bytes on its daemon IPC socket before
dispatching a callback. This supports treating it as a delivery-batch hint. It
does not establish a complete-initial-RRset contract; that missing guarantee is
the reason this implementation cannot safely enable the stricter mixed-answer
policy. The same source documents
[same-queue deallocation and asynchronous descriptor cleanup](https://github.com/apple-oss-distributions/mDNSResponder/blob/main/mDNSShared/dnssd_clientstub.c#L1357),
consistent with the native lifetime measurements above.

The production gate therefore stays off. Enabling requires a reviewed resolver
whose complete-answer semantics can be established, alongside the final app
builds/checks. It must show, rather than assume from a mock:

- A and AAAA completion cannot silently omit an unsafe answer.
- Alias handling fails closed when the canonical/alias identity cannot be
  reviewed; there is no claim of DNSSEC or a reviewed CNAME chain merely because
  an API returned a canonical name.
- Cancellation deallocates pending DNS work promptly; caller deadlines alone
  must not conceal an unbounded resolver operation. The new native ownership
  path has focused LocalOnly operation/descriptor evidence, as described above.
- DNS time is capped by both the three-second DNS limit and the remaining
  end-to-end request budget; late callbacks cannot publish an approved address.

The removed `getaddrinfo` implementation bounded caller waiting but could not
cancel the underlying Darwin resolver call. Its fixed per-lookup timeout could
also overrun the remaining overall deadline. It is not a fallback for enabling
fetching. The DNS-SD replacement improves resource ownership but does not resolve
the separate completeness blocker.

## Resource and lifetime limits

| Resource | Limit/behavior |
| --- | --- |
| Saved pages | 12, explicitly chosen |
| Automatic refresh eligibility | At least 15 minutes; failure backoff capped at 24 hours |
| Redirects | 3; loops rejected |
| Overall fetch budget | 15 seconds across all hops; each DNS/HTTP call receives the smaller remaining budget, checked again before proceeding; final Core regression rerun pending |
| DNS | 3 seconds, also capped by remaining fetch time; actual LocalOnly timeout/cancellation and descriptor drainage checked |
| Connect / TLS handshake | Connect at most 5 seconds or the request's smaller remaining budget; TLS handshake at most 5 seconds and still inside the request lifetime |
| Encrypted bytes received | 1 MiB across the single connection, including TLS records |
| Receive pieces | 4,096 bytes |
| Response head | 8,192-byte conservative pre-decoder budget; maintained parser also caps field/list size and 64 fields |
| Response body | 512 KiB; over-limit declared or delivered body rejected |
| Certificate chain | At most 8 certificates; each at most 32 KiB and 64 KiB DER total at verification |
| Retained extracted text | 24,000 characters; at most 32 semantic sections; title 160 characters |
| HTML suppression nesting | 64; deeper/unfinished suppressed markup fails closed |
| Stored history | 30 days; explicit per-page removal and reset remain available |

`RequestLifetime` synchronizes terminal completion, channel ownership and timers.
It owns the channel during bootstrap initialization, before connect/TLS; a late
initializer cannot acquire ownership after cancellation. Success, error, timeout
or cancellation settles the promise once, cancels the timers and closes the
channel. TLS shutdown does not wait for a peer's `close_notify`. The event loop
is process-lifetime infrastructure, not a request-owned connection or HTTP cache.
No application request is written before the TLS handshake-completed event, and
the client does not configure TLS early data or session resumption.

## Supported pages and deliberate exclusions

Fetching is intentionally narrower than a browser: canonical DNS-name HTTPS
pages on port 443, HTTP/1.0 or HTTP/1.1, exact `text/html`, `text/plain`, or
`application/xhtml+xml` content types, and identity-encoded bounded content.
Plain text remains literal text. The HTML tokenizer is conservative rather than
a standards-complete DOM parser, so malformed markup can make a page unreadable.

Chunked responses, all `Transfer-Encoding` values, compressed bodies, protocol
upgrades, literal-IP URLs and unreviewable aliases are unsupported. DNS results
containing any prohibited address are rejected as a whole. The app policy can
recognize an IPv4-mapped IPv6 answer containing a public IPv4 address; the package
boundary currently rejects that entire mapped prefix. If that mapped address is
selected, the request fails closed. This mismatch reduces compatibility and is
not a bypass; aligning it requires explicit policy and connection-level tests.

Saved legacy pages use a separate frozen read-validation policy. Tightening
network eligibility must not hide their existing history or prevent individual
removal. Reading saved history starts no network request and grants no Daily
Summary authority; choosing Open Source is a separate browser-opening action.
A legacy page that no longer satisfies current URL policy cannot be resumed or
opened through Open Source. Its full address/history may still be inspected and
its explicit Remove button remains available; a supported URL can be added
separately.

## Observed evidence and reproducible commands

Run these from the `Suzzme/` directory. The scripts use synthetic local inputs and
their own temporary directories; the connection script additionally uses the
ignored `Validation/Reports/WatchedTransport-20261021/` work directory. It resolves
pinned build dependencies, generates a temporary CA/leaf certificates, starts
only ephemeral loopback listeners, and tears down its own fixture process. It
does not modify the hosts file, system trust store, app data or provider accounts.

```sh
zsh Validation/watched-transport-check.sh
zsh Validation/watched-url-policy-check.sh
zsh Validation/watched-dns-resolver-check.sh
zsh Validation/watched-extraction-check.sh
zsh Validation/watched-pinned-connection-check.sh
zsh Validation/step10-check.sh
zsh Validation/step11-check.sh
```

| Evidence class | Observed result | Local evidence |
| --- | --- | --- |
| URL/address policy and legacy storage | 216 passed, 0 failed; synthetic address and saved-store fixtures, without real DNS/socket traffic | [`watched-url-policy-check.log`](Validation/Reports/WatchedTransport-20261021/logs/watched-url-policy-check.log) |
| Core orchestration/storage fixtures | 132 passed, 0 failed; includes remaining overall DNS/HTTP budgets, redirects, consent and stale ownership; injected transports are not socket/TLS proof | [`watched-transport-check.log`](Validation/Reports/WatchedTransport-20261021/logs/watched-transport-check.log) |
| Production extractor with hostile synthetic bytes | 49 passed, 0 failed; full 512 KiB repeated/unclosed script/title/comment/attribute inputs completed in at most 0.162 seconds; active workload cancellation returned in 0.0002 seconds; full-title privacy checked before display truncation | [`watched-extraction-check.log`](Validation/Reports/WatchedTransport-20261021/watched-extraction-check.log) |
| Native DNS ownership plus separate callback fixtures | 65 passed, 0 failed; actual LocalOnly negative A/AAAA completion, timeout and cancellation, with six descriptors observed closed after asynchronous DNS-SD cleanup; 40 scripted success/cancellation races | [`dns-resolver-runner-3.log`](Validation/Reports/WatchedTransport-20261021/logs/dns-resolver-runner-3.log), [`DNS checks.log`](Validation/Reports/WatchedTransport-20261021/dns-9R2Ktu/checks.log) |
| Isolated actual socket/TLS suite | 19 test methods / 60 cases; 52 actual anonymous GETs; zero decoy connections and zero private-AIA connections | [`connection-tests.log`](Validation/Reports/WatchedTransport-20261021/connection-fE8wSu/connection-tests.log), [`connection-evidence-summary.json`](Validation/Reports/WatchedTransport-20261021/connection-fE8wSu/connection-evidence-summary.json) |
| Normal Release boundary | Package Release build passed; source guard and inspected Release symbols exclude the test factory/root configuration | [`release-build.log`](Validation/Reports/WatchedTransport-20261021/connection-fE8wSu/release-build.log), [`release-source-guard.log`](Validation/Reports/WatchedTransport-20261021/connection-fE8wSu/release-source-guard.log), [`release-symbols.txt`](Validation/Reports/WatchedTransport-20261021/connection-fE8wSu/release-symbols.txt) |
| Daily context and proactive regressions | Step 10: 194 passed; Step 11: 244 passed, including 21 cached watched provenance/revocation checks; zero failures | [`step10-check.log`](Validation/Reports/WatchedTransport-20261021/logs/step10-check.log), [`step11-check.log`](Validation/Reports/WatchedTransport-20261021/logs/step11-check.log) |
| Final app builds | Unsigned Debug and Release passed for iOS Simulator and macOS, all exit 0; real adapter type-checked with runtime availability off | [Exact commands/results](Validation/Reports/WatchedTransport-20261021/final-builds-results.json), [`LAUNCH_READINESS.md`](LAUNCH_READINESS.md) |
| UI and physical-device acceptance | Final isolated UI inspection in progress; physical-device acceptance remains pending | See [`LAUNCH_READINESS.md`](LAUNCH_READINESS.md) |

The connection tests use the production socket/TLS/parser implementation with a
test-only factory compiled under `WATCHED_TRANSPORT_CONNECTION_TESTS`. It permits
the fixture's loopback endpoint and temporary certificate anchor; those symbols
are absent from normal Release output. The original `.invalid` DNS hostname is
still checked by the SSL certificate policy and observed in SNI and HTTP Host.
Wrong-hostname, expired and untrusted certificates fail before an HTTP request is
sent. A certificate with a private AIA URL does not cause an audit-listener
connection. These are actual local connections, not mocked resolver proof or
traffic to arbitrary internet hosts.

The fixture observes the exact selected endpoint and demonstrates that changing
a separate candidate after capturing the request cannot retarget its socket.
Policy/orchestration fixtures separately exercise DNS changes, mixed answers,
redirect validation and validators. This does not claim that a live public DNS
rebinding service was queried.

One connection-test limitation remains explicit: this host resets an excess
connection to the saturated TCP backlog (`SO_ERROR 54`), so **a stalled TCP
handshake was not induced**. Pre-connect socket ownership, deadline/cancellation
paths and actual stalled TLS closure were checked separately. No test report
should relabel that TCP reset as a successful stalled-handshake test.

## Release decision and owner actions

Keep fetching disabled until the complete-initial-DNS-answer blocker is resolved,
final DNS cancellation/budget evidence is accepted, and focused regressions and
both requested unsigned Debug app builds succeed on the final source. Then review
the explicit production gate, per-page consent UI and installed-device behavior
before changing the availability claim. Existing saved links must remain dormant
until their individual review is confirmed.

This work does not make Suzme launch-ready. Real app/extension signing and App
Groups, installed browser/Share flows, live provider accounts, physical iPhone/Mac
acceptance, accessibility and distribution remain separate gates in
[`LAUNCH_READINESS.md`](LAUNCH_READINESS.md). The owner should review supported
page limitations, confirm per-page consent and inspect/delete behavior on both
platforms, and approve the final release evidence before distribution.
