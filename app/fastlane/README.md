# fastlane — Tally (iOS)

    bundle exec fastlane ios certificates   # one-time: add this app's profile to the match repo
    bundle exec fastlane ios enable_icloud  # one-time: turn on iCloud KV for the App ID
    bundle exec fastlane ios generate       # regenerate Tally.xcodeproj from project.yml
    bundle exec fastlane ios beta           # generate → sign → build → TestFlight

Needs `fastlane/.env` (copy `.env.example`) and `brew install xcodegen`. Full
setup, and where the secrets are backed up, in [../../DISTRIBUTION.md](../../DISTRIBUTION.md).

Set a UTF-8 locale or fastlane complains on every run:

    export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

## Never regenerate the distribution certificate

Team 2AMB7W8PVR has **one** Apple Distribution cert, shared by every app on the
account. `certificates` runs match with `readonly: false` so it can create *this
app's provisioning profile* — it reuses the existing cert and must never mint a
new one, which would revoke signing for kelu, specrgb and bettertaste.
