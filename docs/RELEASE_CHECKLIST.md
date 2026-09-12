# Privacy and release checklist

- [x] No sign-in / accounts
- [x] No CloudKit / iCloud entitlements
- [x] No analytics or telemetry
- [x] Local SwiftData only (`cloudKitDatabase: .none`)
- [x] Secrets stored in Keychain via `KeychainSecretStore`
- [x] Ephemeral URLSession (no shared persistent cache/credentials)
- [x] Secret redaction in resolved/raw views (`SecretRedactor`)
- [x] ATS Option A documented in `docs/ATS_SECURITY.md`
- [x] App Sandbox + outgoing network client entitlement
- [x] Hardened Runtime enabled
- [x] In-memory response size cap (50 MB)
- [x] Schema migration placeholder (`SchemaMigrationPlan`)
- [x] Requests are never auto-sent on launch

## Manual acceptance (spec §40)

Run these locally against a reachable API:

1. Local GET with environment base URL + query
2. Bearer token from Keychain-backed secret variable
3. POST JSON with Content-Type generation
4. Environment switch changes resolved target without editing endpoint
5. DNS/timeout/TLS failures appear in response panel (not modal)
6. Cancel in-flight request shows Cancelled state
