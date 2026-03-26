# Intune Bulk App Assignment Tool

An interactive PowerShell GUI for bulk-assigning Microsoft Intune apps to Azure AD groups — without clicking through each app one at a time.

Designed to solve the lack of bulk app assignment in the Intune portal.
Built to solve the pain of VPP token replacements, tenant migrations, or any situation where you need to reassign a large number of apps quickly.
Small enough you don't need an install.

![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![Platform Windows](https://img.shields.io/badge/Platform-Windows-lightgrey)
![License MIT](https://img.shields.io/badge/License-MIT-green)

---

## What it does

- Connects to Microsoft Graph using your own account (no app registration or secrets required)
- Loads all apps from your Intune tenant with search and platform filtering
- Loads all Azure AD groups with search and multi-select
- Lets you assign any combination of apps to any combination of targets in one click
- Supports **All Users** and **All Devices** as built-in special targets alongside individual groups
- Supports **Required**, **Available**, and **Uninstall** assignment intents
- Automatically disables **All Devices** when **Available** is selected (Intune does not support that combination)
- Skips and clearly labels any assignments that already exist
- Logs every action with colour-coded output (success / skipped / failed)
- Does **not** overwrite existing assignments

---

## Screenshot

<img width="1283" height="851" alt="intunebulkappUI" src="https://github.com/user-attachments/assets/b3f7bc48-56ed-4053-99da-fca65c61dd63" />

---

## Requirements

| Requirement | Details |
|---|---|
| OS | Windows (uses Windows Forms for the GUI) |
| PowerShell | 5.1 or later |
| Module | `Microsoft.Graph` |
| Intune permissions | `DeviceManagementApps.ReadWrite.All` |
| Azure AD permissions | `Group.Read.All` |

You must be a **Global Administrator**, **Intune Administrator**, or have the above Graph API permissions delegated to your account.

---

## Installation

**1. Install the Microsoft Graph module** (one-time, if not already installed):

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

**2. Download the script:**

Clone the repo or download `IntuneAppAssign.ps1` directly.

**3. Unblock the file** (required if downloaded from the internet or a network drive):

```powershell
Unblock-File ".\IntuneAppAssign.ps1"
```

---

## Usage

**Run from a PowerShell terminal:**

```powershell
& ".\IntuneAppAssign.ps1"
```

**Or create a launcher** — make a `.bat` file in the same folder:

```batch
@echo off
powershell.exe -ExecutionPolicy Bypass -File "%~dp0IntuneAppAssign.ps1"
```

Double-clicking the `.bat` will launch the tool without any execution policy prompts.

---

## How to use the tool

1. **Connect to Graph** — click the blue button at the top. A Microsoft login window will open. Sign in with your admin account. Apps and groups load automatically after connecting.

2. **Filter apps** — use the search box to find apps by name, or use the platform dropdown to show only a specific type (e.g. `iosVpp` for Apple VPP apps).

3. **Select apps** — tick individual apps, or use **Select All** to tick everything currently visible in the list. **Clear All** unticks everything.

4. **Choose an intent:**
   - **Required** — force installs on the device automatically
   - **Available** — app appears in Company Portal for the user to install
   - **Uninstall** — removes the app from targeted devices/users

5. **Choose targets** — any combination of the following:
   - **All Users** (Special Targets panel) — targets all licensed users in the tenant via `allLicensedUsersAssignmentTarget`
   - **All Devices** (Special Targets panel) — targets all managed devices via `allDevicesAssignmentTarget`. Greyed out and unavailable when **Available** is selected, as Intune does not support that combination.
   - **Groups** — search and tick one or more Azure AD groups in the Target Groups panel

6. **Assign** — click **ASSIGN APPS TO SELECTED GROUPS**. A confirmation summary shows every app and target before anything happens. Results are logged in real time at the bottom of the window.

---

## Notes

- **Delegated authentication only** — the tool uses your interactive login. It does not require an app registration, client secret, or certificate. Permissions are limited to what your account has in your tenant.
- **Existing assignments are skipped gracefully** — if an app is already assigned to a group with the same intent, it is logged as `SKIP (already assigned)` and does not count as a failure.
- **No data leaves your machine** — all API calls go directly from your machine to Microsoft Graph using your authenticated session.
- **Available assignments** can only target users or user groups — not All Devices or device groups. The tool enforces this by disabling the All Devices button automatically when Available is selected.
- **All Users / All Devices** targets do not require selecting any groups — they can be used on their own or combined with specific groups in the same assignment run.

---

## Common use cases

- Apple VPP token was replaced and all app assignments were wiped
- Migrating apps to new Azure AD groups after a restructure
- Quickly assigning a baseline set of apps to a new group
- Cleaning up and reassigning apps after a tenant-to-tenant migration

---

## License

MIT — free to use, modify, and distribute.
