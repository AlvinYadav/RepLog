# RepLog

Personal voice-first workout + macro tracker. Speak or photograph; Gemini parses; SwiftData stores; charts and weekly AI reports show progress.

## One-time setup

1. **Xcode**: install from the Mac App Store (~12 GB), open once, accept license, install iOS platform support. Xcode → Settings → Accounts → add your Apple ID (creates the free "Personal Team").
2. **API key**: create a free key at [aistudio.google.com](https://aistudio.google.com) → paste into RepLog → Settings on first run (stored in iOS Keychain).
3. **iPhone**: plug in via USB, tap "Trust". After the first deploy attempt, enable Settings → Privacy & Security → Developer Mode, then reboot. After installing, trust the developer cert under Settings → General → VPN & Device Management.
4. Create `Local.xcconfig` next to `project.yml`. It's gitignored, so your IDs stay out of the repo, and it survives `xcodegen generate`:

   ```
   DEVELOPMENT_TEAM = YOUR_TEAM_ID
   REPLOG_DEVICE_ID = YOUR_DEVICE_ID
   ```

   Your team ID is under Xcode → Settings → Accounts, or in the Signing & Capabilities tab. Your device ID comes from `xcrun devicectl list devices`; only `Scripts/redeploy.sh` needs it.

## Development workflow

```sh
xcodegen generate                 # regenerate RepLog.xcodeproj from project.yml (run after adding files)
open RepLog.xcodeproj             # or build from CLI:
xcodebuild -scheme RepLog -destination 'generic/platform=iOS Simulator' build
```

Deploy to phone: select your iPhone as the run destination in Xcode → ⌘R.

## The 7-day rule (free Apple ID)

Free provisioning expires after 7 days — the app stops launching until re-deployed. Manual fallback: plug in, ⌘R (~2 min). `Scripts/redeploy.sh` + a launchd job automate this over Wi-Fi every 6 days (Phase 7).

launchd needs absolute paths, so fill in your username when installing the job. The repo must sit outside `~/Downloads`, `~/Desktop` and `~/Documents`, which macOS blocks background jobs from reading. The plist assumes `~/Developer/RepLog`.

```sh
sed "s|/Users/YOUR_USERNAME|$HOME|g" Scripts/com.alvin.replog.redeploy.plist > ~/Library/LaunchAgents/com.alvin.replog.redeploy.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.alvin.replog.redeploy.plist
```
