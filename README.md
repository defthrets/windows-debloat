# Windows Debloat

A single PowerShell script that removes Microsoft telemetry, kills tracking services, strips pre-installed bloatware, and patches the hosts file with ~170 known ad/tracking domains.

Interactive by default — you choose which sections to apply. One restart and you're done.

---

## Quick Start

Right-click PowerShell → **Run as Administrator**, then:

```powershell
# Preview everything first (no changes made)
.\Debloat-Windows.ps1 -DryRun

# Interactive walk-through (recommended for first run)
.\Debloat-Windows.ps1

# Fully automated — applies everything without prompting
.\Debloat-Windows.ps1 -Full
```

**Restart your PC when done** for all changes to take effect.

---

## What It Does

| # | Section | What changes |
|---|---------|-------------|
| 1 | **Telemetry Services** | Stops and disables 10 background services that phone home to Microsoft |
| 2 | **Registry Privacy Tweaks** | ~50 keys covering telemetry level, advertising ID, Cortana, Copilot, activity history, Start Menu ads, location, clipboard sync, Wi-Fi Sense, CEIP, error reporting, OneDrive, Find My Device |
| 3 | **Scheduled Tasks** | Disables 17 scheduled tasks that collect and upload diagnostic data |
| 4 | **App Permissions** | Denies camera, microphone, location, contacts, and 15 other capabilities to all apps |
| 5 | **Browser Policies** | Group policy settings for Edge, Chrome, and Firefox — turns off metrics, search suggestions, and cloud spell-check; sets Edge tracking to Strict |
| 6 | **Firewall Blocks** | Adds outbound block rules for `CompatTelRunner.exe`, `DeviceCensus.exe`, the Diagnostics Hub service, and `SmartScreen.exe` |
| 7 | **Hosts File** | Null-routes ~170 Microsoft telemetry, Google ad, Facebook pixel, and NVIDIA telemetry domains; flushes DNS |
| 8 | **Bloatware Removal** | Uninstalls ~35 pre-installed apps (Candy Crush, Spotify, Teams Personal, Cortana, Bing apps, Mixed Reality Portal, etc.) from all user profiles and the provisioning store |

---

## Requirements

- Windows 10 22H2+ or Windows 11
- PowerShell 5.1 or later
- Administrator rights

---

## What Might Break

This is the "maximum privacy" configuration. A few things to know:

- **Microsoft Store app updates** may be affected if you block all delivery optimisation
- **Xbox Game Bar** — not touched by this script, but related services (DoSvc) are disabled
- **OneDrive sync** is disabled via policy (files stay local, nothing is deleted)
- **Cortana / Copilot** are disabled; Windows Search still works offline
- **App permissions** are set to Deny for all apps — re-allow per-app in `Settings > Privacy & Security`
- **Teams, Outlook, Skype** are removed but reinstallable from the Microsoft Store

---

## How to Undo

A System Restore point named **Pre-Debloat** is created automatically before any changes. To roll back:

```
Start > System > Recovery > Open System Restore > Pre-Debloat
```

To undo only the hosts file changes, open `C:\Windows\System32\drivers\etc\hosts` in Notepad (as Admin) and delete everything between:

```
# === WINDOWS DEBLOAT ===
...
# === END WINDOWS DEBLOAT ===
```

---

## License

MIT — do whatever you want with it.

**Tested on:** Windows 10 22H2, Windows 11 23H2
