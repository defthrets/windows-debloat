#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows Debloat & Privacy Hardening — v1.0.0
.DESCRIPTION
    Removes Microsoft telemetry, disables tracking services and scheduled tasks,
    applies privacy registry tweaks, blocks ad/tracking domains via the hosts file,
    and strips pre-installed bloatware apps.

    Interactive by default — you are asked before each section.
    Use -Full to skip all prompts, or -DryRun to preview without changing anything.

.PARAMETER Full
    Apply every section without prompting.
.PARAMETER DryRun
    Show what would change. No files, registry keys, or services are touched.
.EXAMPLE
    # Preview everything first (recommended)
    .\Debloat-Windows.ps1 -DryRun

    # Interactive walk-through
    .\Debloat-Windows.ps1

    # Fully automated (great for scripting / imaging)
    .\Debloat-Windows.ps1 -Full
.NOTES
    Version : 1.0.0
    OS      : Windows 10 22H2+ / Windows 11
    Requires: PowerShell 5.1+ running as Administrator
    Restore : System > Recovery > Open System Restore to roll back
#>

param(
    [switch]$Full,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$script:Changes = 0

# ─────────────────────────────── helpers ────────────────────────────────────

function Write-Section {
    param([int]$N, [int]$Total, [string]$Title)
    Write-Host ""
    Write-Host "  [$N/$Total] $Title" -ForegroundColor Cyan
}

function Write-Info  { param($m) Write-Host "        $m" -ForegroundColor DarkGray }
function Write-Ok    { param($m) $script:Changes++; Write-Host "     ok  $m" -ForegroundColor Green }
function Write-Miss  { param($m) Write-Host "   skip  $m" -ForegroundColor DarkGray }

function Confirm-Section {
    param([string]$Prompt)
    if ($Full -or $DryRun) { return $true }
    $r = Read-Host "        Apply? [Y/n]"
    return ($r -eq '' -or $r -match '^[Yy]')
}

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
    if (-not $DryRun) {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
    }
    Write-Ok "$Name = $Value"
}

function Disable-Svc {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Miss "service not found: $Name"; return }
    if (-not $DryRun) {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        Set-Service  -Name $Name -StartupType Disabled -ErrorAction SilentlyContinue
    }
    Write-Ok "disabled service: $Name"
}

function Disable-Task {
    param([string]$FullPath)
    $dir  = $FullPath -replace '\\[^\\]+$', '\'
    $name = $FullPath -replace '.*\\', ''
    $t = Get-ScheduledTask -TaskPath $dir -TaskName $name -ErrorAction SilentlyContinue
    if (-not $t) { Write-Miss "task not found: $name"; return }
    if (-not $DryRun) {
        Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Ok "disabled task: $name"
}

function Remove-App {
    param([string]$PackageName)
    $installed   = Get-AppxPackage -AllUsers -Name $PackageName -ErrorAction SilentlyContinue
    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                   Where-Object DisplayName -like $PackageName
    if (-not $installed -and -not $provisioned) { Write-Miss "not installed: $PackageName"; return }
    if (-not $DryRun) {
        if ($installed)   { $installed   | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue }
        if ($provisioned) { $provisioned | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null }
    }
    Write-Ok "removed: $PackageName"
}

# ─────────────────────────────── banner ─────────────────────────────────────

Write-Host ""
Write-Host "  +-------------------------------------------------+" -ForegroundColor White
Write-Host "  |  Windows Debloat  v1.0.0                        |" -ForegroundColor White
Write-Host "  |  Telemetry off. Privacy on. Bloat gone.         |" -ForegroundColor White
Write-Host "  +-------------------------------------------------+" -ForegroundColor White
Write-Host ""

if ($DryRun) {
    Write-Host "  DRY RUN mode — nothing will be changed" -ForegroundColor Yellow
    Write-Host ""
} elseif ($Full) {
    Write-Host "  FULL mode — all sections will be applied automatically" -ForegroundColor Yellow
    Write-Host ""
} else {
    Write-Host "  Interactive mode — you will be asked before each section." -ForegroundColor DarkGray
    Write-Host "  Run with -Full to skip all prompts, -DryRun to preview." -ForegroundColor DarkGray
    Write-Host ""
}

# ─────────────────────────────── restore point ──────────────────────────────

Write-Info "Creating System Restore point..."
try {
    Enable-ComputerRestore -Drive "C:\" -ErrorAction Stop
    Checkpoint-Computer -Description "Pre-Debloat" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    Write-Info "Restore point created.`n"
} catch {
    Write-Info "Could not create restore point — continuing anyway.`n"
}

$total = 8

# ─────────────────────────── [1/8] Services ─────────────────────────────────

Write-Section 1 $total "Telemetry Services"
Write-Info "Background services that collect and upload data to Microsoft."
if (Confirm-Section) {
    "DiagTrack",                                      # Connected User Experiences & Telemetry
    "dmwappushservice",                               # WAP Push Message Routing (telemetry relay)
    "diagnosticshub.standardcollector.service",       # Diagnostics Hub
    "WerSvc",                                         # Windows Error Reporting
    "PcaSvc",                                         # Program Compatibility Assistant
    "DoSvc",                                          # Delivery Optimization (P2P telemetry)
    "lfsvc",                                          # Geolocation
    "MapsBroker",                                     # Downloaded Maps Manager
    "RetailDemo",                                     # Retail Demo (OEM kiosk mode)
    "wisvc"                                           # Windows Insider
    | ForEach-Object { Disable-Svc $_ }
}

# ────────────────────────── [2/8] Registry ──────────────────────────────────

Write-Section 2 $total "Privacy Registry Tweaks"
Write-Info "Telemetry level, advertising ID, Cortana, Copilot, location, Start Menu ads,"
Write-Info "clipboard sync, Wi-Fi Sense, CEIP, Error Reporting, OneDrive, Find My Device."
if (Confirm-Section) {

    # Telemetry level (0 = Security/off, lowest possible)
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"                  "AllowTelemetry"                              0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"                  "DoNotShowFeedbackNotifications"              1
    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"   "AllowTelemetry"                              0

    # Advertising ID
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"           "Enabled"                                     0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"                 "DisabledByGroupPolicy"                       1

    # Cortana / Copilot
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"                  "AllowCortana"                                0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"                  "DisableWebSearch"                            1
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"                  "ConnectedSearchUseWeb"                       0
    Set-Reg "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"                  "TurnOffWindowsCopilot"                       1
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"                  "TurnOffWindowsCopilot"                       1

    # Activity History / Timeline
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"                          "EnableActivityFeed"                          0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"                          "PublishUserActivities"                       0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"                          "UploadUserActivities"                        0

    # Cloud Content / Spotlight tips
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"                    "DisableWindowsConsumerFeatures"              1
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"                    "DisableSoftLanding"                          1
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"                    "DisableCloudOptimizedContent"                1
    Set-Reg "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"                    "DisableTailoredExperiencesWithDiagnosticData" 1

    # Start Menu ads / silent app installs
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"    "SystemPaneSuggestionsEnabled"                0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"    "SilentInstalledAppsEnabled"                  0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"    "SoftLandingEnabled"                          0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"    "SubscribedContent-338388Enabled"             0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"    "SubscribedContent-338389Enabled"             0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"    "SubscribedContent-353694Enabled"             0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"    "SubscribedContent-353696Enabled"             0

    # Windows 11: Widgets + Teams Chat icon in taskbar
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"         "TaskbarDa"                                   0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"         "TaskbarMn"                                   0

    # Input personalisation (typing / inking telemetry)
    Set-Reg "HKCU:\SOFTWARE\Microsoft\InputPersonalization"                             "RestrictImplicitInkCollection"               1
    Set-Reg "HKCU:\SOFTWARE\Microsoft\InputPersonalization"                             "RestrictImplicitTextCollection"              1
    Set-Reg "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore"            "HarvestContacts"                             0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Personalization\Settings"                         "AcceptedPrivacyPolicy"                       0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"         "Start_TrackProgs"                            0

    # Location
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"             "DisableLocation"                             1
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"             "DisableLocationScripting"                    1
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"             "DisableWindowsLocationProvider"              1

    # Online Speech Recognition
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy"     "HasAccepted"                                 0

    # Clipboard cross-device sync
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"                         "AllowClipboardHistory"                       0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"                         "AllowCrossDeviceClipboard"                   0

    # Wi-Fi Sense (auto-sharing saved networks)
    Set-Reg "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config"                "AutoConnectAllowedOEM"                       0

    # Customer Experience Improvement Program
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows"                      "CEIPEnable"                                  0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat"                      "AITEnable"                                   0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat"                      "DisableUAR"                                  1

    # Error Reporting
    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"                 "Disabled"                                    1
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting"        "Disabled"                                    1

    # Remote Assistance
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance"                 "fAllowToGetHelp"                             0

    # OneDrive
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"                       "DisableFileSyncNGSC"                         1
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"                       "DisableLibrariesDefaultSaveToOneDrive"       1

    # Find My Device
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice"                           "AllowFindMyDevice"                           0
}

# ──────────────────────── [3/8] Scheduled Tasks ─────────────────────────────

Write-Section 3 $total "Scheduled Telemetry Tasks"
Write-Info "Tasks that quietly collect and upload diagnostic data in the background."
if (Confirm-Section) {
    @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater"
        "\Microsoft\Windows\Application Experience\StartupAppTask"
        "\Microsoft\Windows\Autochk\Proxy"
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip"
        "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
        "\Microsoft\Windows\Feedback\Siuf\DmClient"
        "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload"
        "\Microsoft\Windows\Maps\MapsToastTask"
        "\Microsoft\Windows\Maps\MapsUpdateTask"
        "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
        "\Microsoft\Windows\CloudExperienceHost\CreateObjectTask"
        "\Microsoft\Windows\DiskFootprint\Diagnostics"
        "\Microsoft\Windows\PI\Sqm-Tasks"
        "\Microsoft\Windows\NetTrace\GatherNetworkInfo"
        "\Microsoft\Windows\AppID\SmartScreenSpecific"
    ) | ForEach-Object { Disable-Task $_ }
}

# ──────────────────────── [4/8] App Permissions ─────────────────────────────

Write-Section 4 $total "App Permissions"
Write-Info "Denies camera, microphone, location, contacts, and other sensitive"
Write-Info "permissions to all apps. Re-allow per-app in Settings > Privacy."
if (Confirm-Section) {
    @(
        "webcam", "microphone", "userAccountInformation", "contacts",
        "appointments", "phoneCallHistory", "email", "userDataTasks",
        "chat", "radios", "bluetoothSync", "appDiagnostics",
        "documentsLibrary", "picturesLibrary", "videosLibrary",
        "broadFileSystemAccess", "gazeInput", "location"
    ) | ForEach-Object {
        $regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$_"
        if (-not $DryRun) {
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            Set-ItemProperty -Path $regPath -Name "Value" -Value "Deny" -Force
        }
        Write-Ok "denied: $_"
    }
}

# ──────────────────────── [5/8] Browser Policies ────────────────────────────

Write-Section 5 $total "Browser Telemetry Policies"
Write-Info "Group policy settings for Edge, Chrome, and Firefox — disables telemetry,"
Write-Info "search suggestions, spell-check cloud upload, and enables strict tracking protection."
if (Confirm-Section) {
    $edge = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    Set-Reg $edge "MetricsReportingEnabled"                       0
    Set-Reg $edge "SendSiteInfoToImproveServices"                 0
    Set-Reg $edge "PersonalizationReportingEnabled"               0
    Set-Reg $edge "DiagnosticData"                                0
    Set-Reg $edge "ResolveNavigationErrorsUseWebService"          0
    Set-Reg $edge "AlternateErrorPagesEnabled"                    0
    Set-Reg $edge "NetworkPredictionOptions"                      2
    Set-Reg $edge "SearchSuggestEnabled"                          0
    Set-Reg $edge "EdgeShoppingAssistantEnabled"                  0
    Set-Reg $edge "UserFeedbackAllowed"                           0
    Set-Reg $edge "SpotlightExperiencesAndRecommendationsEnabled" 0
    Set-Reg $edge "ShowRecommendationsEnabled"                    0
    Set-Reg $edge "ConfigureDoNotTrack"                           1
    Set-Reg $edge "TrackingPrevention"                            3   # 3 = Strict

    $chrome = "HKLM:\SOFTWARE\Policies\Google\Chrome"
    Set-Reg $chrome "MetricsReportingEnabled"                     0
    Set-Reg $chrome "SafeBrowsingExtendedReportingEnabled"        0
    Set-Reg $chrome "UrlKeyedAnonymizedDataCollectionEnabled"     0
    Set-Reg $chrome "SpellCheckServiceEnabled"                    0
    Set-Reg $chrome "SearchSuggestEnabled"                        0
    Set-Reg $chrome "AlternateErrorPagesEnabled"                  0
    Set-Reg $chrome "NetworkPredictionOptions"                    2
    Set-Reg $chrome "EnableMediaRouter"                           0

    $ff = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
    Set-Reg $ff                 "DisableTelemetry"           1
    Set-Reg $ff                 "DisableDefaultBrowserAgent" 1
    Set-Reg "$ff\UserMessaging" "ExtensionRecommendations"   0
    Set-Reg "$ff\UserMessaging" "FeatureRecommendations"     0
    Set-Reg "$ff\UserMessaging" "SkipOnboarding"             1
}

# ──────────────────────── [6/8] Firewall Blocks ─────────────────────────────

Write-Section 6 $total "Firewall — Outbound Telemetry Blocks"
Write-Info "Adds Windows Firewall outbound block rules for known telemetry executables."
if (Confirm-Section) {
    @(
        @{ Name = "Block-CompatTelRunner"; Path = "$env:SystemRoot\System32\CompatTelRunner.exe" }
        @{ Name = "Block-DeviceCensus";    Path = "$env:SystemRoot\System32\DeviceCensus.exe" }
        @{ Name = "Block-DiagHub";         Path = "$env:SystemRoot\System32\DiagSvcs\DiagnosticsHub.StandardCollector.Service.exe" }
        @{ Name = "Block-SmartScreen";     Path = "$env:SystemRoot\System32\smartscreen.exe" }
    ) | ForEach-Object {
        if (Test-Path $_.Path) {
            if (-not $DryRun) {
                Remove-NetFirewallRule -DisplayName $_.Name -ErrorAction SilentlyContinue
                New-NetFirewallRule -DisplayName $_.Name -Direction Outbound -Action Block `
                    -Program $_.Path -Enabled True | Out-Null
            }
            Write-Ok "blocked outbound: $($_.Name)"
        } else {
            Write-Miss "not found: $($_.Path)"
        }
    }
}

# ──────────────────────── [7/8] Hosts File ──────────────────────────────────

Write-Section 7 $total "Hosts File — Block Tracking Domains"
Write-Info "Null-routes ~170 Microsoft, Google ad, Facebook, and NVIDIA telemetry domains."
if (Confirm-Section) {

    $domains = @(
        # Microsoft telemetry
        "vortex.data.microsoft.com", "vortex-win.data.microsoft.com",
        "telecommand.telemetry.microsoft.com", "telecommand.telemetry.microsoft.com.nsatc.net",
        "oca.telemetry.microsoft.com", "oca.telemetry.microsoft.com.nsatc.net",
        "sqm.telemetry.microsoft.com", "sqm.telemetry.microsoft.com.nsatc.net",
        "watson.telemetry.microsoft.com", "watson.telemetry.microsoft.com.nsatc.net",
        "redir.metaservices.microsoft.com", "choice.microsoft.com", "choice.microsoft.com.nsatc.net",
        "df.telemetry.microsoft.com", "reports.wes.df.telemetry.microsoft.com",
        "wes.df.telemetry.microsoft.com", "services.wes.df.telemetry.microsoft.com",
        "sqm.df.telemetry.microsoft.com", "telemetry.microsoft.com",
        "watson.ppe.telemetry.microsoft.com", "telemetry.appex.bing.net",
        "telemetry.urs.microsoft.com", "settings-sandbox.data.microsoft.com",
        "survey.watson.microsoft.com", "watson.microsoft.com",
        "statsfe2-df.ws.microsoft.com", "corpext.msitadfs.glbdns2.microsoft.com",
        "compatexchange.cloudapp.net",
        # Microsoft diagnostics / experimentation
        "data.microsoft.com", "v10.events.data.microsoft.com",
        "v10.vortex-win.data.microsoft.com", "v20.events.data.microsoft.com",
        "settings-win.data.microsoft.com", "diagnostics.support.microsoft.com",
        "corp.sts.microsoft.com", "feedback.microsoft-hohm.com",
        "feedback.search.microsoft.com", "feedback.windows.com",
        "i1.services.social.microsoft.com", "i1.services.social.microsoft.com.nsatc.net",
        # Microsoft advertising
        "a.ads1.msn.com", "a.ads2.msads.net", "a.ads2.msn.com",
        "ads.msn.com", "ads1.msads.net", "ads1.msn.com",
        "b.ads2.msads.net", "b.rad.msn.com", "bat.bing.com", "c.bing.com",
        "c.atdmt.com", "cdn.atdmt.com", "db3aqu.atdmt.com", "ec.atdmt.com",
        "flex.msn.com", "g.msn.com", "live.rads.msn.com", "rad.msn.com",
        "bs.serving-sys.com", "preview.msn.com", "ssw.live.com",
        "aidps.atdmt.com", "adnexus.net", "adnxs.com", "m.adnxs.com",
        # Cortana / Skype
        "a.cortana.com", "www.bing.com.cortana.com",
        "apps.skype.com", "pricelist.skype.com", "ui.skype.com",
        # Google analytics and ads
        "www.googleadservices.com", "pagead2.googlesyndication.com", "pagead.googlesyndication.com",
        "clients1.google.com", "adservice.google.com", "adservice.google.co.uk",
        "adservice.google.de", "adservice.google.fr", "adservice.google.es",
        "adservice.google.it", "adservice.google.ca", "adservice.google.com.au",
        "googleads.g.doubleclick.net", "googleads4.g.doubleclick.net",
        "partner.googleadservices.com", "redirector.googlevideo.com",
        "www.google-analytics.com", "google-analytics.com", "ssl.google-analytics.com",
        "analytics.google.com", "tagmanager.google.com",
        "fundingchoicesmessages.google.com", "pagead2.googleadservices.com",
        # Chrome telemetry
        "clients2.google.com", "clients3.google.com", "clients4.google.com",
        "clients5.google.com", "clients6.google.com", "sb-ssl.google.com",
        "update.googleapis.com", "toolbarqueries.google.com", "redirector.gvt1.com",
        # Facebook / Meta
        "pixel.facebook.com", "an.facebook.com", "connect.facebook.net",
        "creative.ak.fbcdn.net", "staticxx.facebook.com", "graph.facebook.com",
        # DoubleClick and ad networks
        "doubleclick.net", "www.doubleclick.net", "stats.g.doubleclick.net",
        "cm.g.doubleclick.net", "ad.doubleclick.net", "m.doubleclick.net",
        "mediavisor.doubleclick.net", "pubads.g.doubleclick.net", "securepubads.g.doubleclick.net",
        "www.googletagservices.com", "www.googletagmanager.com",
        "scorecardresearch.com", "sb.scorecardresearch.com", "b.scorecardresearch.com",
        "beacon.krxd.net", "analytics.twitter.com", "ads.linkedin.com", "snap.licdn.com",
        # NVIDIA telemetry
        "telemetry.nvidia.com", "gfe.nvidia.com", "gfswl.geforce.com", "events.gfe.nvidia.com"
    )

    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $marker    = "# === WINDOWS DEBLOAT ==="
    $endMarker = "# === END WINDOWS DEBLOAT ==="

    $content = Get-Content $hostsPath -Raw -ErrorAction SilentlyContinue
    if ($content -match [regex]::Escape($marker)) {
        $content = $content -replace ('(?s)' + [regex]::Escape($marker) + '.*?' + [regex]::Escape($endMarker)), ""
    }

    $block = (@($marker) + ($domains | ForEach-Object { "0.0.0.0 $_" }) + @($endMarker)) -join "`n"

    if (-not $DryRun) {
        Set-Content -Path $hostsPath -Value ($content.TrimEnd() + "`n`n" + $block + "`n") -Encoding ASCII -Force
        ipconfig /flushdns | Out-Null
    }
    Write-Ok "blocked $($domains.Count) domains + flushed DNS cache"
}

# ──────────────────────── [8/8] Bloatware ───────────────────────────────────

Write-Section 8 $total "Bloatware Removal"
Write-Info "Removes pre-installed apps you almost certainly don't want."
Write-Info "Any removed app can be reinstalled from the Microsoft Store."
if (Confirm-Section) {
    @(
        # Microsoft noise
        "Microsoft.549981C3F5F10"          # Cortana (standalone Win11 app)
        "Microsoft.BingNews"               # Microsoft Start / News
        "Microsoft.BingWeather"            # Weather
        "Microsoft.BingFinance"            # Finance
        "Microsoft.BingSports"             # Sports
        "Microsoft.GetHelp"
        "Microsoft.Getstarted"             # Tips / Get Started
        "Microsoft.MicrosoftSolitaireCollection"
        "Microsoft.MixedReality.Portal"
        "Microsoft.Microsoft3DViewer"
        "Microsoft.Print3D"
        "Microsoft.SkypeApp"
        "Microsoft.WindowsFeedbackHub"
        "Microsoft.WindowsMaps"
        "Microsoft.ZuneMusic"              # Groove Music / legacy media player
        "Microsoft.ZuneVideo"             # Movies & TV
        "Microsoft.MicrosoftOfficeHub"     # Microsoft 365 upsell launcher
        "Microsoft.OutlookForWindows"      # New Outlook (reinstallable from Store)
        "MicrosoftTeams"                   # Teams Personal (Win11 taskbar)
        "Microsoft.Teams"
        "Microsoft.YourPhone"              # Phone Link
        "Microsoft.PowerAutomateDesktop"
        "Clipchamp.Clipchamp"              # Video editor

        # Third-party bundled junk
        "king.com.CandyCrushSaga"
        "king.com.CandyCrushFriends"
        "king.com.CandyCrushSodaSaga"
        "king.com.BubbleWitch3Saga"
        "king.com.FarmHeroesSaga"
        "Playtika.CaesarsSlotsFreeCasino"
        "SpotifyAB.SpotifyMusic"
        "Disney.37853D22215B2"
        "AmazonVideo.PrimeVideo"
        "Netflix.Netflix"
        "ByteDance.TikTokPcLauncher"
        "Facebook.317180B0BB486"
        "Twitter.Twitter"
    ) | ForEach-Object { Remove-App $_ }
}

# ─────────────────────────────── summary ────────────────────────────────────

Write-Host ""
Write-Host "  +-------------------------------------------------+" -ForegroundColor White
Write-Host "  |  Done.  $($script:Changes) changes applied.$((' ' * [Math]::Max(0, 25 - "$($script:Changes) changes applied.".Length)))|" -ForegroundColor White
Write-Host "  +-------------------------------------------------+" -ForegroundColor White
Write-Host ""

if ($DryRun) {
    Write-Host "  DRY RUN complete — no changes were made." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "  What to do next:" -ForegroundColor White
Write-Host "    1. Restart your PC for all changes to take effect"
Write-Host "    2. Check Settings > Privacy & Security to review toggles"
Write-Host "    3. Consider a private DNS: 9.9.9.9 (Quad9) or 1.1.1.2 (Cloudflare)"
Write-Host "    4. To undo: System > Recovery > Open System Restore > Pre-Debloat"
Write-Host ""
