# Security

IranLink is network-sensitive software. These rules are enforced by code,
review checklist, and CI (`scripts/security_audit.py` greps for violations).

## Secret handling
- **Never logged**: passwords, UUIDs, tokens, subscription credentials/URLs,
  private keys, full URIs. `LogSanitizer` redacts them from every sink (file,
  viewer, diagnostics export, crash info). Unit-tested with adversarial cases.
- **Never hardcoded**: no tokens, keys, or credentials in source. CI fails on
  `password\s*=\s*["'][^"']` outside test fixtures, `BEGIN PRIVATE KEY`, etc.
- **Process arguments**: the core is launched with a config *file*, never with
  secrets on the command line (visible in Task Manager / `tasklist`).
- **Temp files**: runtime config uses a unique filename, is deleted on stop,
  and lives under the user's private AppData (no shared temp).
- **Clipboard**: cleared after import-paste where the platform allows, and
  never held longer than the import operation; subscription URLs are masked in
  UI after entry (`https://host/•••`).

## Storage
- Secrets at rest: `SecureVault` → Windows DPAPI (`CryptProtectData`,
  `CRYPTPROTECT_UI_FORBIDDEN`, user scope) via `win32` FFI. DPAPI exists since
  Windows 2000, so the Win7 path is identical.
- Fallback: if DPAPI is unavailable (broken profile, service account), an
  AES-256-GCM file vault is used with a per-installation key stored with
  restricted ACLs. Fallback is disclosed in Diagnostics + a one-time notice.
- Non-secrets (names, groups, settings) live in JSON stores with
  `schemaVersion` + migrations; export/import encrypts the secret section and
  warns the user before producing a portable backup.

## Network
- All requests: connect+read timeouts (default 15 s), bounded retries with
  backoff + jitter, user-agent `IranLink/<version>`, cancellation support.
- Subscription fetch honors a per-subscription toggle for cert validation
  (default ON; disabling shows a persistent warning).
- Failed refresh never deletes the last good snapshot.
- No hidden telemetry. Version-0 sends zero analytics. Any future telemetry
  must be opt-in, documented, and listed in Settings → Privacy.

## Privileges
- The app runs unprivileged. UAC elevation happens only for explicit,
  user-confirmed TUN setup, via a separate elevated helper invocation —
  never by relaunching the whole app as admin.
- Installer defaults to per-user (`PrivilegesRequired=lowest`); no firewall
  rules are created silently. If a rule is ever needed it is documented,
  user-confirmed, and removable from Settings.

## Supply chain
- Pinned: Flutter 3.19.6, Xray `XRAY_VERSION` (+`.dgst` verification),
  Inno 6.2.2, GitHub Actions by commit SHA, dependencies by compatible ranges
  resolved on the pinned SDK.
- `SHA256SUMS.txt` is generated for every release artifact.
- `dependabot` is intentionally NOT auto-merging; dependency bumps require the
  Win7-compat review in `docs/windows-compatibility.md`.

## Incident response
`docs/security.md` + `Settings → Diagnostics → Export report` produces a
sanitized bundle (OS, versions, ports, redacted logs). Users are instructed to
review before sharing; the exporter refuses to include vault contents.
