# Fetcher

Native macOS API client for constructing, sending, inspecting, and organizing REST requests.

## Requirements

- macOS 26.5+ (SDK currently available; raise to macOS 27 when tooling supports it)
- Xcode 26.6+

## Features (MVP)

- Local-only SwiftData projects and requests
- Environments and `{{variables}}`
- Keychain-backed secrets
- REST methods, params, headers, auth, JSON/text bodies
- Ephemeral `URLSession` transport with cancel, redirects, and timing
- Native SwiftUI shell with sidebar, toolbar, inspector, and menus
- `NSTextView`-based code editor for bodies/responses

## Distribution / ATS

Option A (direct/notarized): `NSAllowsArbitraryLoads = YES` so arbitrary HTTP endpoints can be tested. See [docs/ATS_SECURITY.md](docs/ATS_SECURITY.md).

## Build

```bash
xcodebuild -project fetcher.xcodeproj -scheme fetcher -destination 'platform=macOS' build
```

## Test

```bash
xcodebuild -project fetcher.xcodeproj -scheme fetcher -destination 'platform=macOS' test
```

## Privacy

- No accounts, cloud sync, analytics, or telemetry
- Network traffic only for user-triggered API requests
- Secrets stored in Keychain, not SwiftData

## Product specification

See [docs/native_macos_api_client_specification.md](docs/native_macos_api_client_specification.md).
