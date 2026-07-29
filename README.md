# AppFileManager

iOS on-device app sandbox file manager — browse, edit, delete, and transfer files from other apps' sandboxes without a computer.

## Quick Start

1. Push this repo to GitHub
2. Go to **Actions** tab — workflow will auto-build IPA
3. Download IPA from **Artifacts**
4. Install via **TrollStore** / **Sideloadly** / **AltStore**

## GitHub Actions (Signed Build)

For signed builds, add these secrets to your repo:

| Secret | Description |
|---|---|
| `APPLE_CERTIFICATE` | Base64-encoded `.p12` certificate |
| `APPLE_CERTIFICATE_PASSWORD` | Certificate password |
| `PROVISION_PROFILE` | Base64-encoded `.mobileprovision` file |
| `TEAM_ID` | Apple Developer Team ID |

## Manual Build (Mac)

```bash
./build.sh --team-id YOUR_TEAM_ID
```

IPA will be at `./build/AppFileManager.ipa`
