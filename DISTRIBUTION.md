# Tally — iOS distribution

iOS-only, shipped to **TestFlight** via **fastlane + match**. Same pattern as
kelu / specrgb / bettertaste on Apple Developer team **2AMB7W8PVR**.

- App name: **Tally Calculator** (App Store) · **Tally** (home screen)
- Bundle ID: `app.tally-calculator` · Apple ID: `6781561026`
- The native `mobile/ios` project is **not committed** — `expo prebuild` regenerates it.
- Signing uses the **shared** certs repo and the **one** Apple Distribution cert the
  whole team reuses. Bootstrapping Tally only adds a new *provisioning profile* — it
  must **never** regenerate the cert (that revokes signing for the other apps).

## One-time setup

1. **Ruby gems** (from `mobile/`):
   ```sh
   cd mobile && bundle install
   ```
2. **Local secrets** — copy and fill in:
   ```sh
   cp fastlane/.env.example fastlane/.env
   ```
   - `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_PATH` — App Store Connect API key
     (`.p8` from Users and Access → Integrations). Reuse the team's existing key.
   - `MATCH_GIT_URL` — the **shared** private certs repo (same URL kelu/specrgb use).
   - `MATCH_PASSWORD` — the match encryption passphrase (same as the other apps).
3. **Register this app's profile** in the match repo (run once):
   ```sh
   npm run certs:ios          # → bundle exec fastlane ios certificates
   ```
   This adds the `app.tally-calculator` App Store profile against the existing cert.

## Shipping a build

Locally:
```sh
cd mobile && npm run ship:ios   # → fastlane ios beta: prebuild → sign → build → TestFlight
```

Or push to `main` (anything under `mobile/**`) and the **iOS TestFlight** GitHub
Action does it on a `macos-15` runner. Manual runs via the Actions tab
(`workflow_dispatch`).

### Required GitHub secrets

Settings → Secrets and variables → Actions:

| Secret | What |
|--------|------|
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | API key issuer ID |
| `ASC_KEY_BASE64` | the `.p8` file, base64-encoded — `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `MATCH_GIT_URL` | SSH URL of the shared certs repo |
| `MATCH_PASSWORD` | match encryption passphrase |
| `MATCH_DEPLOY_KEY` | private SSH **deploy key** with read access to the certs repo |

The build number auto-increments from the latest TestFlight build, so no manual
bumping. To set the marketing version, edit `version` in `mobile/app.json`.

> Note: Expo SDK 56 / RN 0.85 needs a recent Xcode. If the default `macos-15`
> runner image lags, pin one with a `sudo xcode-select -s /Applications/Xcode_XX.app`
> step in the workflow.
