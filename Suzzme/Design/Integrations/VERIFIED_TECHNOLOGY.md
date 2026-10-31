# Suzzme integrations: technical verification

Verified 2026-10-07 against primary official documentation and pinned source. This is an audit; no account connection, GitHub credential, authenticated `tools/list`, or GitHub operation was performed. Documented tools below are expected tools, not runtime-discovered capabilities.

## Protocol and SDK decision

- Current official MCP specification: [2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28). This revision changed the protocol era: no initialization handshake; version, identity and capabilities accompany each request. `server/discover` supports discovery. Older, handshake-based versions are explicitly legacy. See [compatibility matrix](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning).
- Standard bindings are stdio and Streamable HTTP. Modern HTTP removed protocol sessions and the standalone GET notification stream. Changes use `subscriptions/listen`; `tools/list` pagination and `tools/call` remain. Modern requests require matching body metadata and headers. See [transports](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports), [HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http), and [tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools).
- Official SDK listing classifies Swift Tier 3 and TypeScript Tier 1: [SDKs](https://modelcontextprotocol.io/docs/2026-07-28/sdk). Official Swift latest is [0.12.1](https://github.com/modelcontextprotocol/swift-sdk/releases/tag/0.12.1), released May 7; its tag and current main both resolve to `a0ae212ebf6eab5f754c3129608bc5557637e605` (live `git ls-remote`). Its `Version.supported` is exactly `2025-11-25`, `2025-06-18`, `2025-03-26`, `2024-11-05`; it does not implement modern 2026-07-28. [Pinned version source](https://github.com/modelcontextprotocol/swift-sdk/blob/0.12.1/Sources/MCP/Base/Versioning.swift).
- TypeScript latest official release is [v2.3.1](https://github.com/modelcontextprotocol/typescript-sdk/releases/tag/v2.3.1), released October 5. Current packages include `@modelcontextprotocol/client`, `@modelcontextprotocol/server`, `@modelcontextprotocol/core`, and `@modelcontextprotocol/server-legacy`, version 2.3.1. Do not copy historical `@modelcontextprotocol/sdk` APIs without verifying this version.

Recommendation (architectural judgment): Swift can own Suzzme authority, state, persistence, browser bridge and a constrained MCP adapter. A native 0.12.1 adapter can avoid TypeScript for a reviewed GitHub connection that actually supports negotiated legacy 2025-11-25. This is not a current-spec implementation and cannot connect to modern-only custom servers. Do not declare a blanket native-SDK replacement safe. If modern arbitrary HTTPS connectors are required now, evaluate the maintained Tier 1 client/helper rather than implementing the new protocol by hand. Freeze this compatibility decision explicitly before M4; retain native approval authority in either design.

## Verified Swift 0.12.1 APIs

Source cloned to `/private/tmp/suzzme-swift-mcp-0.12.1`. `swift build --target MCP` completed successfully with Xcode 27.0 / Swift 6.4; one upstream NetworkTransport capture warning. No Suzzme dependency was added.

Verified [Client.swift](https://github.com/modelcontextprotocol/swift-sdk/blob/0.12.1/Sources/MCP/Client/Client.swift):

```swift
Client(name:version:configuration: .strict)
client.connect(transport:) // async throws -> Initialize.Result
client.listTools(cursor:) // async throws -> (tools: [Tool], nextCursor: String?)
client.callTool(name:arguments:meta:) // async -> content/isError tuple
client.callTool(name:arguments:meta:) // sync throwing overload -> RequestContext<CallTool.Result>
client.onNotification(ToolListChangedNotification.self, handler:)
client.cancelRequest(_:reason:)
client.disconnect()
```

The singular notification type is `ToolListChangedNotification`. The convenience async tool-call tuple omits `structuredContent`; use the result-bearing overload or typed `send` when that field matters. `connect` runs legacy `initialize` and sends `notifications/initialized` automatically. Its implementation does not explicitly reject an unsupported version returned by a server; the Suzzme adapter must validate against `Version.supported`.

[HTTP transport source](https://github.com/modelcontextprotocol/swift-sdk/blob/0.12.1/Sources/MCP/Base/Transports/HTTPClientTransport.swift) initializer labels are `endpoint`, `configuration`, `streaming`, `sseInitializationTimeout`, `protocolVersion`, `authorizer`, `requestModifier`, `logger`. `requestModifier` supports approved headers; never use it to falsely advertise modern protocol support. `StdioTransport(input:output:logger:)` uses Swift System `FileDescriptor` endpoints and does not launch a subprocess itself. Child-process lifecycle remains native ownership.

The primary Package.swift requires Swift 6.1; an included Package@swift-6.0.swift provides Swift 6.0 compatibility. Platforms are macOS 13 and iOS 16. Its checked-in lockfile resolves EventSource 1.1.0, swift-log 1.6.2, swift-system 1.4.0, swift-nio 2.94.0, swift-collections 1.3.0, swift-atomics 1.3.0, and docc-symbolkit 1.0.0. docc-plugin is a main-branch dependency locked to `e977f65879f82b375a044c8837597f690c067da6`; retain the exact consumer lockfile if adopted. Library MCP depends on SystemPackage, Logging and EventSource; NIO belongs to the conformance executable.

OAuth source exposes `HTTPClientAuthorizer`, `OAuthAuthorizer(configuration:tokenStorage:...)`, `OAuthAuthorizationDelegate.presentAuthorizationURL(_:)`, and `TokenStorage.save/load/clear`. Default storage is in-memory only. OAuthAuthorizer is `@unchecked Sendable` with an explicit single-transport isolation contract; never share one mutable authorizer across account transports. Persist through the native credential boundary if this API is adopted, and audit its automatic auth retry behavior before allowing writes.

The adapter still needs explicit frame/content bounds, reviewed JSON Schema validation, paginated discovery with cycle/page bounds, schema digests, fail-closed schema changes, namespace/account binding, redacted logging, deadlines, safe retry policy, and cancellation/unknown-write reconciliation. These are Suzzme policy obligations, not assertions of SDK coverage.

## Official GitHub MCP server

- [Latest release v2.0.0](https://github.com/github/github-mcp-server/releases/tag/v2.0.0), October 6, 23:34. Annotated tag object `a4c46bbcaa7f0b1babe7139f106586cea498fd9b`; peeled commit `cb290407e20d9cc4a7c338179f4a30287f4e5040`. Live current main was `6330b02c71ade6ecfebe3571d640ba3177cb9390`. Release source cloned to `/private/tmp/suzzme-github-mcp-v2.0.0`. Its Go SDK is 1.8.0; Go module requires 1.26.8.
- [Remote server](https://github.com/github/github-mcp-server/blob/v2.0.0/docs/remote-server.md): `https://api.githubcopilot.com/mcp/`. It is built using this public library plus GitHub internal infrastructure; public tag cannot pin hosted deployment. Authentication supports PAT bearer headers; hosts supporting OAuth must configure their own GitHub App or OAuth App. Do not invent a universal OAuth registration/client secret.
- Local official server: `github-mcp-server stdio`, `GITHUB_PERSONAL_ACCESS_TOKEN`; `--read-only` / `GITHUB_READ_ONLY`; `--toolsets` / `GITHUB_TOOLSETS`; `--tools` / `GITHUB_TOOLS`; `--exclude-tools` / `GITHUB_EXCLUDE_TOOLS`.
- Remote equivalents: `X-MCP-Readonly: true`, `X-MCP-Tools`, `X-MCP-Toolsets`, `X-MCP-Exclude-Tools`; `/readonly` and `/x/{single-toolset}/readonly` supported. Individual tools plus toolsets are additive. Read-only overrides writes; exclusions override explicit inclusion. Default toolsets are `context,issues,pull_requests,repos,users`. Use individual tools for a narrow reviewed starting set, and enforce the application allowlist independently. [Configuration](https://github.com/github/github-mcp-server/blob/v2.0.0/docs/server-configuration.md).
- OAuth challenge scopes for documented `issue_read` / `issue_write` include `repo`; this is broad OAuth scope, not proof of repository-level restriction. [Fine-grained PAT documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) supports selected repositories/permissions, with current scenario limitations and organization approval; runtime API access remains decisive. Classic PAT scope filtering is not present for every token type. Repository allowlists must remain application-enforced.
- Expected initial read names: `get_me`, `issue_read`, `pull_request_read`, `get_file_contents`. Expected issue-read arguments: `method: "get"`, `owner`, `repo`, `issue_number`; other read methods include `get_comments`, `get_sub_issues`, `get_parent`, `get_labels`. Expected write binding: `issue_write` with `method: "create"`, owner/repo/title/body/labels. Do not assume `create_issue` is the current canonical tool. Tool name alone is insufficient for consolidated tools: reviewed capabilities must also bind permitted method and arguments. [Pinned issue implementation](https://github.com/github/github-mcp-server/blob/v2.0.0/pkg/github/issues.go).
- The v2.0.0 README describes protocol-gated structured output for supported 2026-07-28 or newer and retained legacy text output for earlier clients. Actual hosted initialization/discovery must verify this behavior with the intended account; no such discovery occurred in this audit.

## LinkedIn truth

[Official access table](https://learn.microsoft.com/en-us/linkedin/shared/authentication/getting-access) lists self-service profile/email and `w_member_social`; other programs generally require approval. [OIDC](https://learn.microsoft.com/en-us/linkedin/consumer/integrations/self-serve/sign-in-with-linkedin-v2) provides `openid`, `profile`, `email` and the authorized member's limited identity. [Posts API, current September 2026 view](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api?view=li-lms-2026-09) confirms `r_member_social` is restricted to approved users. These permissions do not establish a generic feed, arbitrary full-profile, messaging, or job access capability. No registered/approved Suzzme LinkedIn app was verified. Ship visible-content assistance/drafting; account actions remain unavailable until the exact supported product/grant is verified.

## Local Apple APIs

Installed toolchain: Xcode 27.0 build 27A266a, Apple Swift 6.4; macOS SDK at `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`. Headers verified `SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete`, generic password class, service/account keys, and data protection keychain. Use a single credential boundary. On macOS, accessibility/access-group semantics differ between legacy and data protection keychains; select and verify `kSecUseDataProtectionKeychain` deliberately rather than assuming a ThisDeviceOnly constant makes a legacy item obey iOS semantics. [Apple Keychain](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain).

[ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession) current initializer is `init(url:callback:completionHandler:)` (macOS 14.4+), with `.customScheme(_:)` or `.https(host:path:)`; HTTPS callback host must be associated with the app. The older callbackURLScheme initializer is deprecated in installed headers. `presentationContextProvider`, `prefersEphemeralWebBrowserSession`, `start`, `cancel` were verified. Keep OAuth state/PKCE/issuer checks in native account authorization; a browser authentication session itself grants no action approval.

## Adopted consumer lockfile

After the audit, Suzzme adopted exact MCP 0.12.1 and Swift Logging 1.6.2. The application lockfile, rather than the upstream SDK lockfile, defines the actual transitive graph. Both iOS and macOS use this same SDK dependency.

| Package | Version | Commit |
| --- | --- | --- |
| eventsource | 1.5.1 | `86b5096ac59ab46e66bd1f6377c604bc1dab0bc2` |
| swift-atomics | 1.3.1 | `0442cb5a3f98ab802acb777929fdb446bda11a34` |
| swift-collections | 1.7.2 | `3b69cedbaa49957e97c092ae400bb57602ef941f` |
| swift-log | 1.6.2 | `96a2f8a0fa41e9e09af4585e2724c4e825410b91` |
| swift-nio | 2.104.0 | `6db9d9abd92ad7399b8a564cafbb87d3507245fa` |
| swift-sdk | 0.12.1 | `a0ae212ebf6eab5f754c3129608bc5557637e605` |
| swift-system | 1.8.1 | `869129b7bf4ecc57b97d0193ad29690ca2134750` |

This fixed GitHub adapter negotiates **only legacy 2025-11-25** and fails on any other returned version. Modern arbitrary custom connectors remain disabled. REST identity binding uses GitHub API version 2026-03-10, as documented by [Get the authenticated user](https://docs.github.com/en/rest/users/users#get-the-authenticated-user). No real identity or live tool discovery has been performed.
