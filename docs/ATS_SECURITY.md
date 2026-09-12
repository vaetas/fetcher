# App Transport Security (Option A)

Fetcher uses **Option A** from the product specification: direct/notarized developer distribution with `NSAllowsArbitraryLoads = YES`.

## Rationale

An API client must be able to test arbitrary HTTP and HTTPS endpoints, including local development servers and insecure public HTTP APIs. Restrictive ATS would block a core product workflow.

## Mitigations

- HTTPS remains the recommended default in the UI.
- Secrets are stored in the Keychain, never in SwiftData.
- TLS certificate validation stays on by default.
- Per-host untrusted certificate overrides are deferred to V1.1 and must be explicit when added.
- The app never contacts network endpoints except for user-triggered API requests.

## Tradeoff

Allowing arbitrary loads weakens ATS protections for this process. This is an intentional, documented product decision for a general-purpose API testing tool.
