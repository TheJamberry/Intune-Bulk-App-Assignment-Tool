#Requires -Version 5.1
<#
.SYNOPSIS
    Intune Bulk Assignment Tool — Apps & Enrollment Profiles
.DESCRIPTION
    Mode 1 — App Assignment:
        Select multiple apps, choose an intent (Required / Available / Uninstall),
        pick one or more Azure AD groups, and bulk-assign in a single click.
    Mode 2 — Enrollment Profile Assignment:
        Navigate Windows Autopilot and Apple ADE profile subtrees, view devices
        that do not yet have the selected profile, and bulk-assign them.
.NOTES
    Requires: Microsoft.Graph PowerShell module
    Install:  Install-Module Microsoft.Graph -Scope CurrentUser
    App scopes:        DeviceManagementApps.ReadWrite.All, Group.Read.All
    Enrollment scopes: DeviceManagementServiceConfig.ReadWrite.All,
                       DeviceManagementManagedDevices.ReadWrite.All,
                       Group.ReadWrite.All
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ─────────────────────────────────────────────────────────────────────────────
# Module check — before building any form
# ─────────────────────────────────────────────────────────────────────────────
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication -ErrorAction SilentlyContinue)) {
    $msg  = "The Microsoft.Graph PowerShell module is not installed.`n`n"
    $msg += "Install it with:`n  Install-Module Microsoft.Graph -Scope CurrentUser`n`n"
    $msg += "Then re-run this script."
    [System.Windows.Forms.MessageBox]::Show($msg, "Missing Module",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Shared log helper  ($script:LogBox is set to whichever form's RichTextBox)
# ─────────────────────────────────────────────────────────────────────────────
$script:LogBox = $null

function Write-Log {
    param([string]$Message, [string]$Level = "Info")
    if (-not $script:LogBox) { return }
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "Success" { [System.Drawing.Color]::DarkGreen }
        "Error"   { [System.Drawing.Color]::Crimson }
        "Warning" { [System.Drawing.Color]::DarkOrange }
        default   { [System.Drawing.Color]::Black }
    }
    $script:LogBox.SelectionStart  = $script:LogBox.TextLength
    $script:LogBox.SelectionLength = 0
    $script:LogBox.SelectionColor  = $color
    $script:LogBox.AppendText("[$timestamp] $Message`r`n")
    $script:LogBox.ScrollToCaret()
}

# ─────────────────────────────────────────────────────────────────────────────
# MODE SELECTION DIALOG
# ─────────────────────────────────────────────────────────────────────────────
$script:SelectedMode = $null

$modeForm             = New-Object System.Windows.Forms.Form
$modeForm.Text        = "Intune Bulk Assignment Tool"
$modeForm.Size        = New-Object System.Drawing.Size(500, 320)
$modeForm.StartPosition   = "CenterScreen"
$modeForm.FormBorderStyle = "FixedDialog"
$modeForm.MaximizeBox = $false
$modeForm.MinimizeBox = $false
$modeForm.Font        = New-Object System.Drawing.Font("Segoe UI", 10)
$modeForm.BackColor   = [System.Drawing.Color]::White

$mHdr           = New-Object System.Windows.Forms.Panel
$mHdr.Dock      = "Top"
$mHdr.Height    = 64
$mHdr.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$mHdrLbl            = New-Object System.Windows.Forms.Label
$mHdrLbl.Text       = "Intune Bulk Assignment Tool"
$mHdrLbl.Font       = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
$mHdrLbl.ForeColor  = [System.Drawing.Color]::White
$mHdrLbl.Dock       = "Fill"
$mHdrLbl.TextAlign  = [System.Drawing.ContentAlignment]::MiddleCenter
$mHdr.Controls.Add($mHdrLbl)
$modeForm.Controls.Add($mHdr)

$mSubLbl            = New-Object System.Windows.Forms.Label
$mSubLbl.Text       = "Select a mode to get started:"
$mSubLbl.Font       = New-Object System.Drawing.Font("Segoe UI", 10)
$mSubLbl.ForeColor  = [System.Drawing.Color]::FromArgb(80, 80, 80)
$mSubLbl.Location   = New-Object System.Drawing.Point(0, 76)
$mSubLbl.Size       = New-Object System.Drawing.Size(490, 26)
$mSubLbl.TextAlign  = [System.Drawing.ContentAlignment]::MiddleCenter
$modeForm.Controls.Add($mSubLbl)

$mAppBtn            = New-Object System.Windows.Forms.Button
$mAppBtn.Text       = "App Assignment"
$mAppBtn.Location   = New-Object System.Drawing.Point(50, 114)
$mAppBtn.Size       = New-Object System.Drawing.Size(175, 100)
$mAppBtn.BackColor  = [System.Drawing.Color]::FromArgb(0, 120, 212)
$mAppBtn.ForeColor  = [System.Drawing.Color]::White
$mAppBtn.FlatStyle  = "Flat"
$mAppBtn.Font       = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$mAppBtn.Add_Click({ $script:SelectedMode = "Apps"; $modeForm.Close() })
$modeForm.Controls.Add($mAppBtn)

$mAppSub            = New-Object System.Windows.Forms.Label
$mAppSub.Text       = "Bulk assign apps to Azure AD groups"
$mAppSub.Location   = New-Object System.Drawing.Point(40, 218)
$mAppSub.Size       = New-Object System.Drawing.Size(195, 34)
$mAppSub.ForeColor  = [System.Drawing.Color]::FromArgb(100, 100, 100)
$mAppSub.TextAlign  = [System.Drawing.ContentAlignment]::MiddleCenter
$mAppSub.Font       = New-Object System.Drawing.Font("Segoe UI", 8.5)
$modeForm.Controls.Add($mAppSub)

$mEnrBtn            = New-Object System.Windows.Forms.Button
$mEnrBtn.Text       = "Enrollment Profiles"
$mEnrBtn.Location   = New-Object System.Drawing.Point(275, 114)
$mEnrBtn.Size       = New-Object System.Drawing.Size(175, 100)
$mEnrBtn.BackColor  = [System.Drawing.Color]::FromArgb(16, 124, 16)
$mEnrBtn.ForeColor  = [System.Drawing.Color]::White
$mEnrBtn.FlatStyle  = "Flat"
$mEnrBtn.Font       = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$mEnrBtn.Add_Click({ $script:SelectedMode = "Enrollment"; $modeForm.Close() })
$modeForm.Controls.Add($mEnrBtn)

$mEnrSub            = New-Object System.Windows.Forms.Label
$mEnrSub.Text       = "Assign enrollment profiles to unassigned devices"
$mEnrSub.Location   = New-Object System.Drawing.Point(265, 218)
$mEnrSub.Size       = New-Object System.Drawing.Size(195, 34)
$mEnrSub.ForeColor  = [System.Drawing.Color]::FromArgb(100, 100, 100)
$mEnrSub.TextAlign  = [System.Drawing.ContentAlignment]::MiddleCenter
$mEnrSub.Font       = New-Object System.Drawing.Font("Segoe UI", 8.5)
$modeForm.Controls.Add($mEnrSub)

[void]$modeForm.ShowDialog()
if (-not $script:SelectedMode) { exit }


# =============================================================================
# ══════════════════════  APP ASSIGNMENT MODE  ═════════════════════════════════
# =============================================================================
if ($script:SelectedMode -eq "Apps") {

# ─────────────────────────────────────────────────────────────────────────────
# Script-level state
# ─────────────────────────────────────────────────────────────────────────────
$script:Apps             = [System.Collections.Generic.List[PSObject]]::new()
$script:Groups           = [System.Collections.Generic.List[PSObject]]::new()
$script:SelectedGroupIds = [System.Collections.Generic.HashSet[string]]::new()

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

function Connect-ToGraph {
    $connectButton.Enabled  = $false
    $statusLabel.Text       = "Connecting..."
    $statusLabel.ForeColor  = [System.Drawing.Color]::LightYellow
    [System.Windows.Forms.Application]::DoEvents()

    try {
        Connect-MgGraph -Scopes "DeviceManagementApps.ReadWrite.All", "Group.Read.All" `
            -NoWelcome -ErrorAction Stop

        $ctx                    = Get-MgContext
        $statusLabel.Text       = "Connected: $($ctx.Account)"
        $statusLabel.ForeColor  = [System.Drawing.Color]::LightGreen
        $connectButton.Text     = "Reconnect"
        Write-Log "Connected as $($ctx.Account)" "Success"

        Load-Apps
        Load-Groups
    }
    catch {
        Write-Log "Connection failed: $($_.Exception.Message)" "Error"
        $statusLabel.Text       = "Connection failed — check console for details"
        $statusLabel.ForeColor  = [System.Drawing.Color]::Salmon
    }
    finally {
        $connectButton.Enabled = $true
    }
}

function Load-Apps {
    $loadAppsButton.Enabled = $false
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    Write-Log "Loading apps from Intune..."

    try {
        $script:Apps.Clear()
        $uri = "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps" +
               "?`$top=999&`$select=id,displayName,publisher"

        do {
            $resp = Invoke-MgGraphRequest -Uri $uri -Method GET
            foreach ($a in $resp.value) {
                [void]$script:Apps.Add([PSCustomObject]@{
                    Id          = $a.id
                    DisplayName = $a.displayName
                    Publisher   = $a.publisher
                    Type        = ($a.'@odata.type' -replace '#microsoft\.graph\.', '')
                })
            }
            $uri = $resp.'@odata.nextLink'
        } while ($uri)

        Write-Log "Loaded $($script:Apps.Count) apps" "Success"
        Refresh-AppsList
    }
    catch {
        Write-Log "Failed to load apps: $($_.Exception.Message)" "Error"
    }
    finally {
        $loadAppsButton.Enabled = $true
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

function Refresh-AppsList {
    $searchText     = $appSearchBox.Text.ToLower()
    $platformFilter = $platformCombo.SelectedItem.ToString()

    $appsGrid.SuspendLayout()
    $appsGrid.Rows.Clear()

    $filtered = $script:Apps | Where-Object {
        ($searchText     -eq "" -or $_.DisplayName.ToLower().Contains($searchText)) -and
        ($platformFilter -eq "All Platforms" -or $_.Type -like "*$platformFilter*")
    } | Sort-Object DisplayName

    foreach ($app in $filtered) {
        $rowIdx = $appsGrid.Rows.Add()
        $row    = $appsGrid.Rows[$rowIdx]
        $row.Cells["ColCheck"].Value     = $false
        $row.Cells["ColName"].Value      = $app.DisplayName
        $row.Cells["ColType"].Value      = $app.Type
        $row.Cells["ColPublisher"].Value = $app.Publisher
        $row.Tag = $app.Id
    }

    $appsGrid.ResumeLayout()
    $appsCountLabel.Text = "$($filtered.Count) of $($script:Apps.Count) apps"
}

function Load-Groups {
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    Write-Log "Loading groups from Azure AD..."

    try {
        $script:Groups.Clear()
        $uri = "https://graph.microsoft.com/v1.0/groups" +
               "?`$top=999&`$select=id,displayName,groupTypes,securityEnabled"

        do {
            $resp = Invoke-MgGraphRequest -Uri $uri -Method GET
            foreach ($g in $resp.value) {
                [void]$script:Groups.Add([PSCustomObject]@{
                    Id          = $g.id
                    DisplayName = $g.displayName
                    IsM365      = ($g.groupTypes -contains "Unified")
                    IsSecurity  = [bool]$g.securityEnabled
                })
            }
            $uri = $resp.'@odata.nextLink'
        } while ($uri)

        Write-Log "Loaded $($script:Groups.Count) groups" "Success"
        Refresh-GroupsList
    }
    catch {
        Write-Log "Failed to load groups: $($_.Exception.Message)" "Error"
    }
    finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

function Refresh-GroupsList {
    $searchText = $groupSearchBox.Text.ToLower()

    $groupsList.BeginUpdate()
    $groupsList.Items.Clear()

    $filtered = $script:Groups | Where-Object {
        $searchText -eq "" -or $_.DisplayName.ToLower().Contains($searchText)
    } | Sort-Object DisplayName

    foreach ($group in $filtered) {
        $idx = $groupsList.Items.Add($group.DisplayName)
        if ($script:SelectedGroupIds.Contains($group.Id)) {
            $groupsList.SetItemChecked($idx, $true)
        }
    }

    $groupsList.EndUpdate()
    $groupCountLabel.Text = "$($filtered.Count) of $($script:Groups.Count) groups"
}

function Start-Assignment {
    # Collect selected apps
    $selectedApps = [System.Collections.Generic.List[PSObject]]::new()
    foreach ($row in $appsGrid.Rows) {
        if ($row.Cells["ColCheck"].Value -eq $true) {
            $app = $script:Apps | Where-Object { $_.Id -eq $row.Tag } | Select-Object -First 1
            if ($app) { [void]$selectedApps.Add($app) }
        }
    }

    # Intent
    $intent = if ($radioRequired.Checked)  { "required" }
              elseif ($radioAvailable.Checked) { "available" }
              else { "uninstall" }

    # Build unified target list (special built-ins + selected groups)
    $targets = [System.Collections.Generic.List[PSObject]]::new()

    if ($chkAllUsers.Checked) {
        [void]$targets.Add([PSCustomObject]@{
            Label     = "All Users"
            ODataType = "#microsoft.graph.allLicensedUsersAssignmentTarget"
            GroupId   = $null
        })
    }
    if ($chkAllDevices.Checked) {
        [void]$targets.Add([PSCustomObject]@{
            Label     = "All Devices"
            ODataType = "#microsoft.graph.allDevicesAssignmentTarget"
            GroupId   = $null
        })
    }
    foreach ($g in @($script:Groups | Where-Object { $script:SelectedGroupIds.Contains($_.Id) })) {
        [void]$targets.Add([PSCustomObject]@{
            Label     = $g.DisplayName
            ODataType = "#microsoft.graph.groupAssignmentTarget"
            GroupId   = $g.Id
        })
    }

    # Validate
    if ($selectedApps.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select at least one app.",
            "Nothing Selected",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    if ($targets.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select at least one target (All Users, All Devices, or a group).",
            "Nothing Selected",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    # Build confirmation message
    $appLines    = ($selectedApps | Select-Object -First 8 | ForEach-Object { "  • $($_.DisplayName)" }) -join "`n"
    $targetLines = ($targets      | Select-Object -First 8 | ForEach-Object { "  • $($_.Label)" })       -join "`n"
    if ($selectedApps.Count -gt 8) { $appLines    += "`n  ...and $($selectedApps.Count - 8) more" }
    if ($targets.Count      -gt 8) { $targetLines += "`n  ...and $($targets.Count - 8) more" }

    $confirmMsg = @"
About to create $($selectedApps.Count * $targets.Count) assignment(s):

APPS ($($selectedApps.Count)):
$appLines

INTENT:  $($intent.ToUpper())

TARGETS ($($targets.Count)):
$targetLines

Existing assignments to these targets will be left intact — only new
entries will be added. Proceed?
"@

    $result = [System.Windows.Forms.MessageBox]::Show(
        $confirmMsg, "Confirm Assignments",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)

    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    # ── Execute ───────────────────────────────────────────────────────────────
    $assignButton.Enabled  = $false
    $progressBar.Maximum   = $selectedApps.Count * $targets.Count
    $progressBar.Value     = 0
    $okCount = 0; $skipCount = 0; $errCount = 0

    foreach ($app in $selectedApps) {
        foreach ($target in $targets) {
            try {
                $targetObj = [ordered]@{ "@odata.type" = $target.ODataType }
                if ($target.GroupId) { $targetObj["groupId"] = $target.GroupId }

                $body = [ordered]@{
                    "@odata.type" = "#microsoft.graph.mobileAppAssignment"
                    intent        = $intent
                    target        = $targetObj
                } | ConvertTo-Json -Depth 5

                $uri = "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps/$($app.Id)/assignments"
                Invoke-MgGraphRequest -Uri $uri -Method POST -Body $body -ContentType "application/json" -ErrorAction Stop

                Write-Log "OK  '$($app.DisplayName)'  →  '$($target.Label)'  [$intent]" "Success"
                $okCount++
            }
            catch {
                $errMsg = $_.Exception.Message
                if ($errMsg -match "400|409|BadRequest|Bad Request|already exist|Conflict") {
                    Write-Log "SKIP (already assigned): '$($app.DisplayName)' → '$($target.Label)'" "Warning"
                    $skipCount++
                }
                else {
                    Write-Log "FAIL '$($app.DisplayName)' → '$($target.Label)': $errMsg" "Error"
                    $errCount++
                }
            }

            $progressBar.Value++
            [System.Windows.Forms.Application]::DoEvents()
        }
    }

    $assignButton.Enabled = $true

    $summary = "Done — Created: $okCount | Already existed: $skipCount | Failed: $errCount"
    Write-Log $summary $(if ($errCount -eq 0) { "Success" } else { "Warning" })

    $icon = if ($errCount -eq 0) { [System.Windows.Forms.MessageBoxIcon]::Information }
            else                  { [System.Windows.Forms.MessageBoxIcon]::Warning }

    [System.Windows.Forms.MessageBox]::Show($summary, "Assignments Complete", `
        [System.Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
}

# ─────────────────────────────────────────────────────────────────────────────
# BUILD FORM — App Assignment
# ─────────────────────────────────────────────────────────────────────────────

$form = New-Object System.Windows.Forms.Form
$form.Text          = "Intune — Bulk App Assignment Tool"
$form.Size          = New-Object System.Drawing.Size(1300, 860)
$form.StartPosition = "CenterScreen"
$form.MinimumSize   = New-Object System.Drawing.Size(1000, 700)
$form.Font          = New-Object System.Drawing.Font("Segoe UI", 9)

# ── Header bar ───────────────────────────────────────────────────────────────
$headerPanel            = New-Object System.Windows.Forms.Panel
$headerPanel.Dock       = "Top"
$headerPanel.Height     = 52
$headerPanel.BackColor  = [System.Drawing.Color]::FromArgb(0, 120, 212)

$connectButton          = New-Object System.Windows.Forms.Button
$connectButton.Text     = "Connect to Graph"
$connectButton.Location = New-Object System.Drawing.Point(10, 10)
$connectButton.Size     = New-Object System.Drawing.Size(155, 32)
$connectButton.BackColor = [System.Drawing.Color]::White
$connectButton.FlatStyle = "Flat"
$connectButton.Font     = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$connectButton.Add_Click({ Connect-ToGraph })
$headerPanel.Controls.Add($connectButton)

$statusLabel            = New-Object System.Windows.Forms.Label
$statusLabel.Text       = "Not connected — click 'Connect to Graph' to begin"
$statusLabel.ForeColor  = [System.Drawing.Color]::LightYellow
$statusLabel.Location   = New-Object System.Drawing.Point(178, 17)
$statusLabel.Size       = New-Object System.Drawing.Size(900, 20)
$statusLabel.Font       = New-Object System.Drawing.Font("Segoe UI", 9)
$headerPanel.Controls.Add($statusLabel)

# ── Log panel (bottom) ───────────────────────────────────────────────────────
$logPanel               = New-Object System.Windows.Forms.Panel
$logPanel.Dock          = "Bottom"
$logPanel.Height        = 180
$logPanel.BackColor     = [System.Drawing.Color]::FromArgb(240, 240, 240)

$logTitleLabel          = New-Object System.Windows.Forms.Label
$logTitleLabel.Text     = "  Activity Log"
$logTitleLabel.Dock     = "Top"
$logTitleLabel.Height   = 22
$logTitleLabel.Font     = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$logTitleLabel.BackColor = [System.Drawing.Color]::FromArgb(225, 225, 225)
$logBox                 = New-Object System.Windows.Forms.RichTextBox
$logBox.Dock            = "Fill"
$logBox.ReadOnly        = $true
$logBox.Font            = New-Object System.Drawing.Font("Consolas", 8.5)
$logBox.BackColor       = [System.Drawing.Color]::FromArgb(252, 252, 252)
$logBox.BorderStyle     = "None"
$logPanel.Controls.Add($logBox)
$logPanel.Controls.Add($logTitleLabel)
$script:LogBox = $logBox

# ── Main split (apps | config) ───────────────────────────────────────────────
$splitMain             = New-Object System.Windows.Forms.SplitContainer
$splitMain.Dock        = "Fill"
$splitMain.Orientation = "Vertical"
$form.Add_Load({
    $splitMain.Panel1MinSize    = 480
    $splitMain.Panel2MinSize    = 340
    $splitMain.SplitterDistance = [int]($form.ClientSize.Width * 0.60)
})

# ── LEFT — Apps ──────────────────────────────────────────────────────────────
$appsGroupBox      = New-Object System.Windows.Forms.GroupBox
$appsGroupBox.Text = "Apps"
$appsGroupBox.Dock = "Fill"

$appsCtrlPanel         = New-Object System.Windows.Forms.Panel
$appsCtrlPanel.Dock    = "Top"
$appsCtrlPanel.Height  = 78
$appsCtrlPanel.Padding = New-Object System.Windows.Forms.Padding(5, 4, 5, 0)

$appSearchBox                   = New-Object System.Windows.Forms.TextBox
$appSearchBox.PlaceholderText   = "Search apps..."
$appSearchBox.Location          = New-Object System.Drawing.Point(8, 8)
$appSearchBox.Size              = New-Object System.Drawing.Size(270, 24)
$appSearchBox.Add_TextChanged({ Refresh-AppsList })
$appsCtrlPanel.Controls.Add($appSearchBox)

$platformCombo              = New-Object System.Windows.Forms.ComboBox
$platformCombo.Location     = New-Object System.Drawing.Point(288, 8)
$platformCombo.Size         = New-Object System.Drawing.Size(180, 24)
$platformCombo.DropDownStyle = "DropDownList"
[void]$platformCombo.Items.AddRange(@(
    "All Platforms", "iosVpp", "iosStore", "win32",
    "winMobileMSI", "androidStore", "webApp", "microsoftStoreForBusiness"
))
$platformCombo.SelectedIndex = 0
$platformCombo.Add_SelectedIndexChanged({ Refresh-AppsList })
$appsCtrlPanel.Controls.Add($platformCombo)

$loadAppsButton          = New-Object System.Windows.Forms.Button
$loadAppsButton.Text     = "Refresh"
$loadAppsButton.Location = New-Object System.Drawing.Point(478, 7)
$loadAppsButton.Size     = New-Object System.Drawing.Size(72, 26)
$loadAppsButton.Add_Click({ Load-Apps })
$appsCtrlPanel.Controls.Add($loadAppsButton)

$selectAllAppsBtn          = New-Object System.Windows.Forms.Button
$selectAllAppsBtn.Text     = "Select All"
$selectAllAppsBtn.Location = New-Object System.Drawing.Point(8, 40)
$selectAllAppsBtn.Size     = New-Object System.Drawing.Size(82, 26)
$selectAllAppsBtn.Add_Click({
    foreach ($row in $appsGrid.Rows) { $row.Cells["ColCheck"].Value = $true }
})
$appsCtrlPanel.Controls.Add($selectAllAppsBtn)

$clearAllAppsBtn          = New-Object System.Windows.Forms.Button
$clearAllAppsBtn.Text     = "Clear All"
$clearAllAppsBtn.Location = New-Object System.Drawing.Point(96, 40)
$clearAllAppsBtn.Size     = New-Object System.Drawing.Size(82, 26)
$clearAllAppsBtn.Add_Click({
    foreach ($row in $appsGrid.Rows) { $row.Cells["ColCheck"].Value = $false }
})
$appsCtrlPanel.Controls.Add($clearAllAppsBtn)

$appsCountLabel          = New-Object System.Windows.Forms.Label
$appsCountLabel.Text     = "No apps loaded"
$appsCountLabel.Location = New-Object System.Drawing.Point(190, 46)
$appsCountLabel.Size     = New-Object System.Drawing.Size(280, 18)
$appsCountLabel.ForeColor = [System.Drawing.Color]::Gray
$appsCtrlPanel.Controls.Add($appsCountLabel)

$appsGrid                           = New-Object System.Windows.Forms.DataGridView
$appsGrid.Dock                      = "Fill"
$appsGrid.AllowUserToAddRows        = $false
$appsGrid.AllowUserToDeleteRows     = $false
$appsGrid.ReadOnly                  = $false
$appsGrid.SelectionMode             = "FullRowSelect"
$appsGrid.MultiSelect               = $false
$appsGrid.RowHeadersVisible         = $false
$appsGrid.AutoSizeColumnsMode       = "Fill"
$appsGrid.BackgroundColor           = [System.Drawing.Color]::White
$appsGrid.BorderStyle               = "None"
$appsGrid.GridColor                 = [System.Drawing.Color]::FromArgb(220, 220, 220)
$appsGrid.CellBorderStyle           = "SingleHorizontal"
$appsGrid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 252)
$appsGrid.RowTemplate.Height        = 24

$appsGrid.Add_CellClick({
    param($s, $e)
    if ($e.RowIndex -ge 0 -and $e.ColumnIndex -ne 0) {
        $cur = $appsGrid.Rows[$e.RowIndex].Cells["ColCheck"].Value
        $appsGrid.Rows[$e.RowIndex].Cells["ColCheck"].Value = -not $cur
    }
})

$colCheck              = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colCheck.Name         = "ColCheck"
$colCheck.HeaderText   = ""
$colCheck.Width        = 35
$colCheck.AutoSizeMode = "None"
[void]$appsGrid.Columns.Add($colCheck)

$colName             = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colName.Name        = "ColName"
$colName.HeaderText  = "App Name"
$colName.ReadOnly    = $true
[void]$appsGrid.Columns.Add($colName)

$colType             = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colType.Name        = "ColType"
$colType.HeaderText  = "Type"
$colType.ReadOnly    = $true
$colType.Width       = 130
$colType.AutoSizeMode = "None"
[void]$appsGrid.Columns.Add($colType)

$colPub              = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPub.Name         = "ColPublisher"
$colPub.HeaderText   = "Publisher"
$colPub.ReadOnly     = $true
$colPub.Width        = 170
$colPub.AutoSizeMode = "None"
[void]$appsGrid.Columns.Add($colPub)

$appsGroupBox.Controls.Add($appsGrid)
$appsGroupBox.Controls.Add($appsCtrlPanel)
$splitMain.Panel1.Controls.Add($appsGroupBox)

# ── RIGHT — Intent + Groups + Action ─────────────────────────────────────────
$rightLayout              = New-Object System.Windows.Forms.TableLayoutPanel
$rightLayout.Dock         = "Fill"
$rightLayout.ColumnCount  = 1
$rightLayout.RowCount     = 5
$rightLayout.Padding      = New-Object System.Windows.Forms.Padding(6, 4, 6, 4)

[void]$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Absolute, 118)))
[void]$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Absolute, 72)))
[void]$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Percent, 100)))
[void]$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Absolute, 58)))
[void]$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Absolute, 28)))

# Intent
$intentGroup      = New-Object System.Windows.Forms.GroupBox
$intentGroup.Text = "Assignment Intent"
$intentGroup.Dock = "Fill"

$radioRequired          = New-Object System.Windows.Forms.RadioButton
$radioRequired.Text     = "Required  (force install on device)"
$radioRequired.Location = New-Object System.Drawing.Point(12, 22)
$radioRequired.Size     = New-Object System.Drawing.Size(300, 22)
$intentGroup.Controls.Add($radioRequired)

$radioAvailable          = New-Object System.Windows.Forms.RadioButton
$radioAvailable.Text     = "Available  (user installs from Company Portal)"
$radioAvailable.Location = New-Object System.Drawing.Point(12, 48)
$radioAvailable.Size     = New-Object System.Drawing.Size(310, 22)
$radioAvailable.Checked  = $true
$intentGroup.Controls.Add($radioAvailable)

$radioUninstall          = New-Object System.Windows.Forms.RadioButton
$radioUninstall.Text     = "Uninstall"
$radioUninstall.Location = New-Object System.Drawing.Point(12, 74)
$radioUninstall.Size     = New-Object System.Drawing.Size(200, 22)
$intentGroup.Controls.Add($radioUninstall)

$radioAvailable.Add_CheckedChanged({
    if ($radioAvailable.Checked) {
        $chkAllDevices.Checked   = $false
        $chkAllDevices.BackColor = [System.Drawing.SystemColors]::Control
        $chkAllDevices.ForeColor = [System.Drawing.Color]::Black
        $chkAllDevices.Enabled   = $false
    }
})
$radioRequired.Add_CheckedChanged({
    if ($radioRequired.Checked) { $chkAllDevices.Enabled = $true }
})
$radioUninstall.Add_CheckedChanged({
    if ($radioUninstall.Checked) { $chkAllDevices.Enabled = $true }
})

$rightLayout.Controls.Add($intentGroup, 0, 0)

# Special Targets
$specialGroup      = New-Object System.Windows.Forms.GroupBox
$specialGroup.Text = "Special Targets"
$specialGroup.Dock = "Fill"

$chkAllUsers              = New-Object System.Windows.Forms.CheckBox
$chkAllUsers.Text         = "All Users"
$chkAllUsers.Appearance   = [System.Windows.Forms.Appearance]::Button
$chkAllUsers.Location     = New-Object System.Drawing.Point(10, 22)
$chkAllUsers.Size         = New-Object System.Drawing.Size(130, 36)
$chkAllUsers.TextAlign    = [System.Drawing.ContentAlignment]::MiddleCenter
$chkAllUsers.FlatStyle    = "Flat"
$chkAllUsers.Font         = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$chkAllUsers.Add_CheckedChanged({
    if ($chkAllUsers.Checked) {
        $chkAllUsers.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
        $chkAllUsers.ForeColor = [System.Drawing.Color]::White
    } else {
        $chkAllUsers.BackColor = [System.Drawing.SystemColors]::Control
        $chkAllUsers.ForeColor = [System.Drawing.Color]::Black
    }
})
$specialGroup.Controls.Add($chkAllUsers)

$chkAllDevices              = New-Object System.Windows.Forms.CheckBox
$chkAllDevices.Text         = "All Devices"
$chkAllDevices.Appearance   = [System.Windows.Forms.Appearance]::Button
$chkAllDevices.Location     = New-Object System.Drawing.Point(150, 22)
$chkAllDevices.Size         = New-Object System.Drawing.Size(130, 36)
$chkAllDevices.TextAlign    = [System.Drawing.ContentAlignment]::MiddleCenter
$chkAllDevices.FlatStyle    = "Flat"
$chkAllDevices.Font         = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$chkAllDevices.Add_CheckedChanged({
    if ($chkAllDevices.Checked) {
        $chkAllDevices.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
        $chkAllDevices.ForeColor = [System.Drawing.Color]::White
    } else {
        $chkAllDevices.BackColor = [System.Drawing.SystemColors]::Control
        $chkAllDevices.ForeColor = [System.Drawing.Color]::Black
    }
})
$specialGroup.Controls.Add($chkAllDevices)
$chkAllDevices.Enabled = $false

$rightLayout.Controls.Add($specialGroup, 0, 1)

# Groups
$groupsGroup      = New-Object System.Windows.Forms.GroupBox
$groupsGroup.Text = "Target Groups"
$groupsGroup.Dock = "Fill"

$groupsCtrlPanel        = New-Object System.Windows.Forms.Panel
$groupsCtrlPanel.Dock   = "Top"
$groupsCtrlPanel.Height = 60

$groupSearchBox                 = New-Object System.Windows.Forms.TextBox
$groupSearchBox.PlaceholderText = "Search groups..."
$groupSearchBox.Location        = New-Object System.Drawing.Point(5, 5)
$groupSearchBox.Size            = New-Object System.Drawing.Size(310, 24)
$groupSearchBox.Add_TextChanged({ Refresh-GroupsList })
$groupsCtrlPanel.Controls.Add($groupSearchBox)

$selectAllGroupsBtn          = New-Object System.Windows.Forms.Button
$selectAllGroupsBtn.Text     = "Select All"
$selectAllGroupsBtn.Location = New-Object System.Drawing.Point(5, 33)
$selectAllGroupsBtn.Size     = New-Object System.Drawing.Size(82, 24)
$selectAllGroupsBtn.Add_Click({
    for ($i = 0; $i -lt $groupsList.Items.Count; $i++) {
        $groupsList.SetItemChecked($i, $true)
        $gn = $groupsList.Items[$i].ToString()
        $g  = $script:Groups | Where-Object { $_.DisplayName -eq $gn } | Select-Object -First 1
        if ($g) { [void]$script:SelectedGroupIds.Add($g.Id) }
    }
})
$groupsCtrlPanel.Controls.Add($selectAllGroupsBtn)

$clearAllGroupsBtn          = New-Object System.Windows.Forms.Button
$clearAllGroupsBtn.Text     = "Clear All"
$clearAllGroupsBtn.Location = New-Object System.Drawing.Point(93, 33)
$clearAllGroupsBtn.Size     = New-Object System.Drawing.Size(82, 24)
$clearAllGroupsBtn.Add_Click({
    for ($i = 0; $i -lt $groupsList.Items.Count; $i++) {
        $groupsList.SetItemChecked($i, $false)
    }
    $script:SelectedGroupIds.Clear()
})
$groupsCtrlPanel.Controls.Add($clearAllGroupsBtn)

$groupCountLabel          = New-Object System.Windows.Forms.Label
$groupCountLabel.Text     = "No groups loaded"
$groupCountLabel.Location = New-Object System.Drawing.Point(185, 37)
$groupCountLabel.Size     = New-Object System.Drawing.Size(150, 18)
$groupCountLabel.ForeColor = [System.Drawing.Color]::Gray
$groupsCtrlPanel.Controls.Add($groupCountLabel)

$groupsList              = New-Object System.Windows.Forms.CheckedListBox
$groupsList.Dock         = "Fill"
$groupsList.CheckOnClick = $true
$groupsList.Add_ItemCheck({
    param($sender, $e)
    $gn = $groupsList.Items[$e.Index].ToString()
    $g  = $script:Groups | Where-Object { $_.DisplayName -eq $gn } | Select-Object -First 1
    if ($g) {
        if ($e.NewValue -eq [System.Windows.Forms.CheckState]::Checked) {
            [void]$script:SelectedGroupIds.Add($g.Id)
        } else {
            [void]$script:SelectedGroupIds.Remove($g.Id)
        }
    }
})

$groupsGroup.Controls.Add($groupsList)
$groupsGroup.Controls.Add($groupsCtrlPanel)
$rightLayout.Controls.Add($groupsGroup, 0, 2)

# Assign button
$assignButton           = New-Object System.Windows.Forms.Button
$assignButton.Text      = "ASSIGN APPS TO SELECTED GROUPS"
$assignButton.Dock      = "Fill"
$assignButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$assignButton.ForeColor = [System.Drawing.Color]::White
$assignButton.FlatStyle = "Flat"
$assignButton.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$assignButton.Add_Click({ Start-Assignment })
$rightLayout.Controls.Add($assignButton, 0, 3)

# Progress bar
$progressBar        = New-Object System.Windows.Forms.ProgressBar
$progressBar.Dock   = "Fill"
$progressBar.Style  = "Continuous"
$rightLayout.Controls.Add($progressBar, 0, 4)

$splitMain.Panel2.Controls.Add($rightLayout)

# Assemble form (order matters for Dock layout)
$form.Controls.Add($splitMain)    # Fill — added first so it gets remaining space
$form.Controls.Add($logPanel)     # Bottom
$form.Controls.Add($headerPanel)  # Top

Write-Log "Intune Bulk App Assignment Tool ready."
Write-Log "Required module: Microsoft.Graph  |  Install: Install-Module Microsoft.Graph -Scope CurrentUser"
[void]$form.ShowDialog()

} # ── end App Assignment mode ─────────────────────────────────────────────────


# =============================================================================
# ══════════════════  ENROLLMENT PROFILE MODE  ════════════════════════════════
# =============================================================================
else {

# ─────────────────────────────────────────────────────────────────────────────
# State
# ─────────────────────────────────────────────────────────────────────────────
$script:EP_SelectedProfile = $null   # { Type, Id, Name, TokenId, TokenName, Platform }
$script:EP_Devices         = [System.Collections.Generic.List[PSObject]]::new()
$script:EP_DEPTokens       = [System.Collections.Generic.List[PSObject]]::new()
$script:EP_ProfileNames    = @{}     # profileId → displayName  (for resolving current profile in device list)

# ─────────────────────────────────────────────────────────────────────────────
# ENROLLMENT PROFILE FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-EPConnect {
    $ep_connectBtn.Enabled  = $false
    $ep_statusLbl.Text      = "Connecting..."
    $ep_statusLbl.ForeColor = [System.Drawing.Color]::LightYellow
    [System.Windows.Forms.Application]::DoEvents()
    try {
        Connect-MgGraph -Scopes @(
            "DeviceManagementServiceConfig.ReadWrite.All",
            "DeviceManagementManagedDevices.ReadWrite.All",
            "Group.ReadWrite.All"
        ) -NoWelcome -ErrorAction Stop

        $ctx = Get-MgContext
        $ep_statusLbl.Text      = "Connected: $($ctx.Account)"
        $ep_statusLbl.ForeColor = [System.Drawing.Color]::LightGreen
        $ep_connectBtn.Text     = "Reconnect"
        Write-Log "Connected as $($ctx.Account)" "Success"
        Initialize-EPTree
    }
    catch {
        Write-Log "Connection failed: $($_.Exception.Message)" "Error"
        $ep_statusLbl.Text      = "Connection failed — check Activity Log"
        $ep_statusLbl.ForeColor = [System.Drawing.Color]::Salmon
    }
    finally {
        $ep_connectBtn.Enabled = $true
    }
}

function Initialize-EPTree {
    $ep_treeView.Nodes.Clear()
    $ep_selProfLbl.Text     = "No profile selected"
    $ep_selProfLbl.ForeColor = [System.Drawing.Color]::Gray
    $script:EP_ProfileNames = @{}
    Write-Log "Loading enrollment profile tree..."
    $ep_treeView.BeginUpdate()

    # All device-management endpoints use the beta API — v1.0 returns 400 for
    # several enrollment endpoints in many tenants.
    $base = "https://graph.microsoft.com/beta"

    try {
        # ── Windows ───────────────────────────────────────────────────────────
        $winNode     = $ep_treeView.Nodes.Add("win", "Windows")
        $winNode.Tag = "platform"

        # Autopilot Deployment Profiles
        $apNode     = $winNode.Nodes.Add("autopilot", "Autopilot Deployment Profiles")
        $apNode.Tag = "category"
        try {
            $uri = "$base/deviceManagement/windowsAutopilotDeploymentProfiles?`$select=id,displayName&`$top=999"
            do {
                $resp = Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction Stop
                foreach ($p in $resp.value | Sort-Object displayName) {
                    $script:EP_ProfileNames[$p.id] = $p.displayName
                    $n     = $apNode.Nodes.Add($p.id, $p.displayName)
                    $n.Tag = [PSCustomObject]@{ Type = "autopilot"; Id = $p.id; Name = $p.displayName; TokenId = $null; TokenName = $null; Platform = "Windows" }
                }
                $uri = $resp.'@odata.nextLink'
            } while ($uri)
            Write-Log "Autopilot: loaded" "Success"
        }
        catch { Write-Log "Autopilot profiles: $($_.Exception.Message)" "Warning" }

        # Windows Enrollment Configurations (ESP, Hello for Business, etc.)
        $winCfgNode     = $winNode.Nodes.Add("wincfg", "Enrollment Configurations")
        $winCfgNode.Tag = "category"
        try {
            $uri = "$base/deviceManagement/deviceEnrollmentConfigurations?`$select=id,displayName,deviceEnrollmentConfigurationType&`$top=999"
            $allCfgs = [System.Collections.Generic.List[PSObject]]::new()
            do {
                $resp = Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction Stop
                foreach ($c in $resp.value) { [void]$allCfgs.Add($c) }
                $uri = $resp.'@odata.nextLink'
            } while ($uri)

            $winTypes = @(
                "windows10EnrollmentCompletionPageConfiguration",
                "defaultWindows10EnrollmentCompletionPageConfiguration",
                "windowsHelloForBusiness","defaultWindowsHelloForBusiness",
                "deviceComanagementAuthorityConfiguration","deviceLimit","defaultDeviceLimit"
            )
            foreach ($c in $allCfgs | Where-Object { $_.deviceEnrollmentConfigurationType -in $winTypes } | Sort-Object displayName) {
                $script:EP_ProfileNames[$c.id] = $c.displayName
                $typeShort = ($c.deviceEnrollmentConfigurationType -replace 'default|Configuration|ForBusiness|Authority|Enrollment','').Trim()
                $n     = $winCfgNode.Nodes.Add($c.id, "$($c.displayName)  [$typeShort]")
                $n.Tag = [PSCustomObject]@{ Type = "enrollmentConfig"; Id = $c.id; Name = $c.displayName; TokenId = $null; TokenName = $null; Platform = "Windows" }
            }
            Write-Log "Windows enrollment configs: loaded" "Success"
        }
        catch { Write-Log "Windows enrollment configs: $($_.Exception.Message)" "Warning" }

        # ── Apple (iOS / iPadOS / macOS) ──────────────────────────────────────
        $appleNode     = $ep_treeView.Nodes.Add("apple", "Apple  (iOS / iPadOS / macOS)")
        $appleNode.Tag = "platform"

        # Automated Device Enrollment (Apple Business Manager / School Manager)
        $adeNode     = $appleNode.Nodes.Add("ade", "Automated Device Enrollment  (ABM / ASM)")
        $adeNode.Tag = "category"
        $script:EP_DEPTokens.Clear()
        try {
            $uri = "$base/deviceManagement/depOnboardingSettings?`$select=id,tokenName,appleIdentifier&`$top=999"
            $tokResp = Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction Stop

            if ($tokResp.value.Count -eq 0) {
                Write-Log "No ABM/ASM tokens found in this tenant" "Warning"
            }

            foreach ($tok in $tokResp.value | Sort-Object { if ($_.tokenName) { $_.tokenName } else { $_.appleIdentifier } }) {
                $tokName = if ($tok.tokenName -and $tok.tokenName -ne '') { $tok.tokenName } else { $tok.appleIdentifier }
                [void]$script:EP_DEPTokens.Add([PSCustomObject]@{ Id = $tok.id; Name = $tokName })

                $tokNode     = $adeNode.Nodes.Add($tok.id, "Token:  $tokName")
                $tokNode.Tag = "deptoken"

                try {
                    # Do NOT use $select here — 'platform' is not a base property on
                    # enrollmentProfile and causes Graph to return 400. Fetch all fields.
                    $pUri  = "$base/deviceManagement/depOnboardingSettings/$($tok.id)/enrollmentProfiles?`$top=999"
                    $pResp = Invoke-MgGraphRequest -Uri $pUri -Method GET -ErrorAction Stop
                    foreach ($p in $pResp.value | Sort-Object displayName) {
                        $script:EP_ProfileNames[$p.id] = $p.displayName
                        # Derive OS label from the OData type returned in the payload
                        $odataType = $p.'@odata.type'
                        $platLabel = if     ($odataType -match 'depMacOS')  { "  [macOS]"  }
                                     elseif ($odataType -match 'depIOS')    { "  [iOS]"    }
                                     elseif ($odataType -match '[Mm]ac')    { "  [macOS]"  }
                                     elseif ($odataType -match '[Ii][Pp]ad'){ "  [iPadOS]" }
                                     elseif ($p.platform)                   { "  [$($p.platform)]" }
                                     else                                   { "" }
                        $n     = $tokNode.Nodes.Add($p.id, "$($p.displayName)$platLabel")
                        $n.Tag = [PSCustomObject]@{ Type = "dep"; Id = $p.id; Name = $p.displayName; TokenId = $tok.id; TokenName = $tokName; Platform = "Apple" }
                    }
                    Write-Log "  ABM Token '$tokName': $($pResp.value.Count) profile(s)" "Success"
                }
                catch {
                    Write-Log "  ABM Token '$tokName' profiles: $($_.Exception.Message)" "Warning"
                    $n     = $tokNode.Nodes.Add("_ep_err_$($tok.id)", "(Could not load profiles — see log)")
                    $n.Tag = "info"
                }
            }
        }
        catch { Write-Log "ABM/ASM tokens: $($_.Exception.Message)" "Warning" }

        # Apple User / Device Enrollment (Configurator, BYOD)
        $aueNode     = $appleNode.Nodes.Add("aue", "User and Device Enrollment  (Configurator / BYOD)")
        $aueNode.Tag = "category"
        try {
            $uri = "$base/deviceManagement/appleUserInitiatedEnrollmentProfiles?`$select=id,displayName,platform&`$top=999"
            $resp = Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction Stop
            foreach ($p in $resp.value | Sort-Object displayName) {
                $script:EP_ProfileNames[$p.id] = $p.displayName
                $platLabel = if ($p.platform) { "  [$($p.platform)]" } else { "" }
                $n     = $aueNode.Nodes.Add($p.id, "$($p.displayName)$platLabel")
                $n.Tag = [PSCustomObject]@{ Type = "appleUserEnrollment"; Id = $p.id; Name = $p.displayName; TokenId = $null; TokenName = $null; Platform = "Apple" }
            }
            Write-Log "Apple User/Device Enrollment: $($resp.value.Count) profile(s)" "Success"
        }
        catch { Write-Log "Apple User/Device Enrollment: $($_.Exception.Message)" "Warning" }

        # Enrollment Restrictions (platform restrictions for iOS/macOS)
        $appleCfgNode     = $appleNode.Nodes.Add("applecfg", "Enrollment Restrictions")
        $appleCfgNode.Tag = "category"
        try {
            $uri = "$base/deviceManagement/deviceEnrollmentConfigurations?`$select=id,displayName,deviceEnrollmentConfigurationType&`$top=999"
            $resp = Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction Stop
            foreach ($c in $resp.value | Where-Object { $_.deviceEnrollmentConfigurationType -eq "singlePlatformRestriction" } | Sort-Object displayName) {
                $script:EP_ProfileNames[$c.id] = $c.displayName
                $n     = $appleCfgNode.Nodes.Add("acfg_$($c.id)", $c.displayName)
                $n.Tag = [PSCustomObject]@{ Type = "enrollmentConfig"; Id = $c.id; Name = $c.displayName; TokenId = $null; TokenName = $null; Platform = "Apple" }
            }
            Write-Log "Apple enrollment restrictions: loaded" "Success"
        }
        catch { Write-Log "Apple enrollment restrictions: $($_.Exception.Message)" "Warning" }

        # ── Android ───────────────────────────────────────────────────────────
        $andNode     = $ep_treeView.Nodes.Add("android", "Android")
        $andNode.Tag = "platform"

        $andDoNode     = $andNode.Nodes.Add("anddo", "Corporate-Owned Device Enrollment")
        $andDoNode.Tag = "category"
        try {
            $uri = "$base/deviceManagement/androidDeviceOwnerEnrollmentProfiles?`$select=id,displayName,enrollmentMode&`$top=999"
            $resp = Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction Stop
            foreach ($p in $resp.value | Sort-Object displayName) {
                $script:EP_ProfileNames[$p.id] = $p.displayName
                $modeLabel = if ($p.enrollmentMode) { "  ($($p.enrollmentMode))" } else { "" }
                $n     = $andDoNode.Nodes.Add($p.id, "$($p.displayName)$modeLabel")
                $n.Tag = [PSCustomObject]@{ Type = "enrollmentConfig"; Id = $p.id; Name = $p.displayName; TokenId = $null; TokenName = $null; Platform = "Android" }
            }
            Write-Log "Android Corporate-Owned: $($resp.value.Count) profile(s)" "Success"
        }
        catch { Write-Log "Android Corporate-Owned (requires DeviceManagementConfiguration.Read scope): $($_.Exception.Message)" "Warning" }

        $ep_treeView.ExpandAll()
        Write-Log "Profile tree loaded." "Success"
    }
    catch {
        Write-Log "Tree load error: $($_.Exception.Message)" "Error"
    }
    finally {
        $ep_treeView.EndUpdate()
    }
}

# Called when user clicks a profile node in the right-hand tree.
# Just records the selection and updates the UI state — devices are already loaded.
function Select-EPProfile {
    param($ep_prof)
    $script:EP_SelectedProfile = $ep_prof

    $typeLabel = switch ($ep_prof.Type) {
        "autopilot"           { "Autopilot" }
        "dep"                 { "ADE / ABM" }
        "appleUserEnrollment" { "Apple User Enrollment" }
        "enrollmentConfig"    { "Enrollment Config" }
        default               { $ep_prof.Type }
    }
    if ($ep_prof.Type -eq "dep" -and $ep_prof.TokenName) {
        $ep_selProfLbl.Text = "Token: $($ep_prof.TokenName)   |   Profile: $($ep_prof.Name)  [$typeLabel]"
    } else {
        $ep_selProfLbl.Text = "$($ep_prof.Name)  [$typeLabel]"
    }
    $ep_selProfLbl.ForeColor = [System.Drawing.Color]::FromArgb(16, 124, 16)

    $anyChecked = ($ep_devGrid.Rows | Where-Object { $_.Cells["EP_ColCheck"].Value -eq $true }).Count -gt 0
    $ep_assignBtn.Enabled = $anyChecked
    Write-Log "Profile selected: $($ep_selProfLbl.Text)"
}

# Loads ALL ADE devices from every ABM token into $script:EP_Devices.
function Get-EPAllDevices {
    if ($script:EP_DEPTokens.Count -eq 0) {
        Write-Log "No ABM tokens loaded — connect first and ensure the profile tree has loaded." "Warning"
        return
    }
    $ep_loadDevBtn.Enabled = $false
    $ep_form.Cursor        = [System.Windows.Forms.Cursors]::WaitCursor
    $ep_devCountLbl.Text   = "Loading..."
    $script:EP_Devices.Clear()
    $ep_devGrid.Rows.Clear()
    [System.Windows.Forms.Application]::DoEvents()

    try {
        foreach ($tok in $script:EP_DEPTokens) {
            Write-Log "Loading devices from token '$($tok.Name)'..."
            try {
                $uri = "https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings/$($tok.Id)/importedAppleDeviceIdentities?`$top=999"
                do {
                    $r = Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction Stop
                    foreach ($d in $r.value) {
                        if ($d.isDeleted) { continue }

                        $osType = switch -Regex ($d.productType) {
                            "iPad"        { "iPadOS" }
                            "iPhone|iPod" { "iOS"    }
                            "Mac"         { "macOS"  }
                            default       { "Apple"  }
                        }
                        $currentProfile = if ($d.enrollmentProfileId) {
                            $n = $script:EP_ProfileNames[$d.enrollmentProfileId]
                            if ($n) { $n } else { "(unknown profile)" }
                        } elseif ($d.requestedEnrollmentProfileId) {
                            $n = $script:EP_ProfileNames[$d.requestedEnrollmentProfileId]
                            if ($n) { "Pending: $n" } else { "Pending: (unknown)" }
                        } else {
                            "No profile assigned"
                        }

                        [void]$script:EP_Devices.Add([PSCustomObject]@{
                            Id             = $d.id
                            Serial         = $d.serialNumber
                            Model          = $d.productType
                            OS             = $osType
                            CurrentProfile = $currentProfile
                            TokenId        = $tok.Id
                            TokenName      = $tok.Name
                        })
                    }
                    $uri = $r.'@odata.nextLink'
                } while ($uri)
                Write-Log "  Token '$($tok.Name)': $($script:EP_Devices.Count) device(s) so far" "Success"
            }
            catch {
                Write-Log "  Token '$($tok.Name)' device load failed: $($_.Exception.Message)" "Error"
            }
        }
        Write-Log "Total: $($script:EP_Devices.Count) ADE device(s) loaded" "Success"
    }
    finally {
        $ep_loadDevBtn.Enabled = $true
        $ep_form.Cursor        = [System.Windows.Forms.Cursors]::Default
        Update-EPDeviceGrid
    }
}

# (Get-EPDEPDevices removed — devices are now loaded all-at-once by Get-EPAllDevices)

# Returns the selected group PSObject, or $null if the user cancelled.
# $noGroupMsg is shown when there are no groups at all.
function Show-EPGroupPicker {
    param(
        [System.Collections.Generic.List[PSObject]]$groups,
        [string]$noGroupMsg
    )
    if ($groups.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show($noGroupMsg, "No Groups",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $null
    }
    if ($groups.Count -eq 1) { return $groups[0] }

    $pickForm                  = New-Object System.Windows.Forms.Form
    $pickForm.Text             = "Select Target Group"
    $pickForm.Size             = New-Object System.Drawing.Size(420, 280)
    $pickForm.StartPosition    = "CenterParent"
    $pickForm.FormBorderStyle  = "FixedDialog"
    $pickForm.MaximizeBox      = $false
    $pickForm.Font             = New-Object System.Drawing.Font("Segoe UI", 9)

    $pLbl          = New-Object System.Windows.Forms.Label
    $pLbl.Text     = "This profile is assigned to multiple groups.`nSelect the group to add the devices to:"
    $pLbl.Location = New-Object System.Drawing.Point(12, 12)
    $pLbl.Size     = New-Object System.Drawing.Size(386, 38)
    $pickForm.Controls.Add($pLbl)

    $pList          = New-Object System.Windows.Forms.ListBox
    $pList.Location = New-Object System.Drawing.Point(12, 55)
    $pList.Size     = New-Object System.Drawing.Size(386, 140)
    foreach ($g in $groups) { [void]$pList.Items.Add($g.DisplayName) }
    $pList.SelectedIndex = 0
    $pickForm.Controls.Add($pList)

    $pOk              = New-Object System.Windows.Forms.Button
    $pOk.Text         = "OK"
    $pOk.Location     = New-Object System.Drawing.Point(210, 205)
    $pOk.Size         = New-Object System.Drawing.Size(86, 28)
    $pOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $pickForm.Controls.Add($pOk)
    $pickForm.AcceptButton = $pOk

    $pCancel              = New-Object System.Windows.Forms.Button
    $pCancel.Text         = "Cancel"
    $pCancel.Location     = New-Object System.Drawing.Point(308, 205)
    $pCancel.Size         = New-Object System.Drawing.Size(86, 28)
    $pCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $pickForm.Controls.Add($pCancel)

    if ($pickForm.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return $groups | Where-Object { $_.DisplayName -eq $pList.SelectedItem } | Select-Object -First 1
}

function Update-EPDeviceGrid {
    $typeFilter = $ep_typeCombo.SelectedItem.ToString()
    $searchTxt  = $ep_devSearchBox.Text.ToLower()

    $ep_devGrid.SuspendLayout()
    $ep_devGrid.Rows.Clear()

    $filtered = $script:EP_Devices | Where-Object {
        ($typeFilter -eq "All Types" -or $_.OS -like "*$typeFilter*") -and
        ($searchTxt  -eq "" -or $_.Serial.ToLower().Contains($searchTxt) -or $_.Model.ToLower().Contains($searchTxt))
    } | Sort-Object Serial

    foreach ($d in $filtered) {
        $rowIdx = $ep_devGrid.Rows.Add()
        $row    = $ep_devGrid.Rows[$rowIdx]
        $row.Cells["EP_ColCheck"].Value          = $false
        $row.Cells["EP_ColSerial"].Value         = $d.Serial
        $row.Cells["EP_ColModel"].Value          = $d.Model
        $row.Cells["EP_ColOS"].Value             = $d.OS
        $row.Cells["EP_ColCurProfile"].Value     = $d.CurrentProfile
        $row.Cells["EP_ColToken"].Value          = $d.TokenName
        $row.Tag = $d.Id
    }

    $ep_devGrid.ResumeLayout()
    $ep_devCountLbl.Text = "$($filtered.Count) of $($script:EP_Devices.Count) device(s) shown"
}

function Invoke-EPAssignment {
    $ep_prof = $script:EP_SelectedProfile
    if (-not $ep_prof) {
        [System.Windows.Forms.MessageBox]::Show("Please select an enrollment profile from the tree on the right.", "No Profile Selected",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    # Collect checked rows
    $selected = [System.Collections.Generic.List[PSObject]]::new()
    foreach ($row in $ep_devGrid.Rows) {
        if ($row.Cells["EP_ColCheck"].Value -eq $true) {
            $dev = $script:EP_Devices | Where-Object { $_.Id -eq $row.Tag } | Select-Object -First 1
            if ($dev) { [void]$selected.Add($dev) }
        }
    }

    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select at least one device.", "Nothing Selected",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $result = [System.Windows.Forms.MessageBox]::Show(
        "Assign $($selected.Count) device(s) to profile '$($ep_prof.Name)'?`n`nProceed?",
        "Confirm Assignment",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $ep_assignBtn.Enabled   = $false
    $ep_progressBar.Maximum = $selected.Count
    $ep_progressBar.Value   = 0
    $okCount  = 0
    $errCount = 0

    # All devices shown are ADE/DEP — each device carries its own TokenId
    Set-EPDEP $selected $ep_prof ([ref]$okCount) ([ref]$errCount)

    $ep_assignBtn.Enabled = $true
    $summary = "Done — Assigned: $okCount | Failed: $errCount"
    Write-Log $summary $(if ($errCount -eq 0) { "Success" } else { "Warning" })
    [System.Windows.Forms.MessageBox]::Show($summary, "Assignment Complete",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $(if ($errCount -eq 0) { [System.Windows.Forms.MessageBoxIcon]::Information }
          else { [System.Windows.Forms.MessageBoxIcon]::Warning })) | Out-Null

    # Reload devices so the grid reflects the newly assigned profile
    Get-EPAllDevices
}

function Set-EPAutopilot {
    param($devices, $ep_prof, [ref]$okCount, [ref]$errCount)

    # Discover which AAD groups this Autopilot profile is assigned to
    $groups = [System.Collections.Generic.List[PSObject]]::new()
    try {
        $uri  = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeploymentProfiles/$($ep_prof.Id)/assignments"
        $resp = Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction Stop
        foreach ($a in $resp.value) {
            if ($a.target.'@odata.type' -eq "#microsoft.graph.groupAssignmentTarget" -and $a.target.groupId) {
                try {
                    $g = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$($a.target.groupId)?`$select=id,displayName" -Method GET
                    [void]$groups.Add([PSCustomObject]@{ Id = $g.id; DisplayName = $g.displayName })
                } catch { }
            }
        }
    }
    catch {
        Write-Log "Could not retrieve profile group assignments: $($_.Exception.Message)" "Error"
        $errCount.Value += $devices.Count
        return
    }

    $noGrpMsg    = "The Autopilot profile '$($ep_prof.Name)' has no Azure AD group assignments.`n`n" +
                   "Assign this profile to at least one group in Intune first, then retry."
    $targetGroup = Show-EPGroupPicker $groups $noGrpMsg
    if (-not $targetGroup) { $errCount.Value += $devices.Count; return }

    Write-Log "Adding $($devices.Count) device(s) to group '$($targetGroup.DisplayName)'..."

    foreach ($dev in $devices) {
        try {
            if (-not $dev.AadDeviceId) {
                Write-Log "SKIP '$($dev.Serial)' — no Azure AD Device ID (device may not be registered)" "Warning"
                $errCount.Value++
            }
            else {
                $body = '{"@odata.id":"https://graph.microsoft.com/v1.0/directoryObjects/' + $dev.AadDeviceId + '"}'
                Invoke-MgGraphRequest `
                    -Uri "https://graph.microsoft.com/v1.0/groups/$($targetGroup.Id)/members/`$ref" `
                    -Method POST -Body $body -ContentType "application/json" -ErrorAction Stop
                Write-Log "OK  '$($dev.Serial)' → '$($targetGroup.DisplayName)'" "Success"
                $okCount.Value++
            }
        }
        catch {
            $errMsg = $_.Exception.Message
            if ($errMsg -match "already exist|One or more added object references already exist") {
                Write-Log "SKIP '$($dev.Serial)' — already in group" "Warning"
                $okCount.Value++
            }
            else {
                Write-Log "FAIL '$($dev.Serial)': $errMsg" "Error"
                $errCount.Value++
            }
        }
        $ep_progressBar.Value++
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Set-EPDEP {
    param($devices, $ep_prof, [ref]$okCount, [ref]$errCount)
    Write-Log "Assigning $($devices.Count) ADE device(s) to profile '$($ep_prof.Name)'..."

    # The Graph API action for assigning ADE profiles is:
    #   POST .../enrollmentProfiles/{profileId}/updateDeviceProfileAssignment
    # with a body of { "deviceIds": [ "serial1", "serial2", ... ] }
    # Devices must belong to the same token as the profile.
    # Group by TokenId so each token gets one POST call per batch.
    $byToken = $devices | Group-Object -Property TokenId

    foreach ($grp in $byToken) {
        $tokenId = $grp.Name
        $serials  = @($grp.Group | ForEach-Object { $_.Serial })

        # Batch in chunks of 100 (API limit)
        $batchSize = 100
        for ($i = 0; $i -lt $serials.Count; $i += $batchSize) {
            $chunk = $serials[$i .. [Math]::Min($i + $batchSize - 1, $serials.Count - 1)]
            try {
                $uri  = "https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings/$tokenId/enrollmentProfiles/$($ep_prof.Id)/updateDeviceProfileAssignment"
                $body = @{ deviceIds = $chunk } | ConvertTo-Json -Compress
                Invoke-MgGraphRequest -Uri $uri -Method POST -Body $body -ContentType "application/json" -ErrorAction Stop

                foreach ($s in $chunk) {
                    Write-Log "OK  '$s' → '$($ep_prof.Name)'" "Success"
                    $okCount.Value++
                    $ep_progressBar.Value++
                    [System.Windows.Forms.Application]::DoEvents()
                }
            }
            catch {
                Write-Log "FAIL batch [$($chunk -join ', ')]: $($_.Exception.Message)" "Error"
                $errCount.Value += $chunk.Count
                $ep_progressBar.Value += $chunk.Count
                [System.Windows.Forms.Application]::DoEvents()
            }
        }
    }
}

# Assigns devices to a group-based enrollment config by adding the device's AAD
# object to one of the groups that the config is already assigned to.
function Set-EPEnrollmentConfig {
    param($devices, $ep_prof, [ref]$okCount, [ref]$errCount)

    # Resolve which config endpoint to query for assignments —
    # appleUserInitiatedEnrollmentProfiles uses its own assignments navigation
    $assignUri = if ($ep_prof.Type -eq "appleUserEnrollment") {
        "https://graph.microsoft.com/beta/deviceManagement/appleUserInitiatedEnrollmentProfiles/$($ep_prof.Id)/assignments"
    } else {
        "https://graph.microsoft.com/v1.0/deviceManagement/deviceEnrollmentConfigurations/$($ep_prof.Id)/assignments"
    }

    $groups = [System.Collections.Generic.List[PSObject]]::new()
    try {
        $resp = Invoke-MgGraphRequest -Uri $assignUri -Method GET -ErrorAction Stop
        foreach ($a in $resp.value) {
            if ($a.target.'@odata.type' -eq "#microsoft.graph.groupAssignmentTarget" -and $a.target.groupId) {
                try {
                    $g = Invoke-MgGraphRequest `
                        -Uri "https://graph.microsoft.com/v1.0/groups/$($a.target.groupId)?`$select=id,displayName" `
                        -Method GET
                    [void]$groups.Add([PSCustomObject]@{ Id = $g.id; DisplayName = $g.displayName })
                } catch { }
            }
        }
    }
    catch {
        Write-Log "Could not get config assignments: $($_.Exception.Message)" "Error"
        $errCount.Value += $devices.Count
        return
    }

    $noGrpMsg    = "The config '$($ep_prof.Name)' has no Azure AD group assignments.`n`n" +
                   "Assign this config to at least one group in Intune first, then retry."
    $targetGroup = Show-EPGroupPicker $groups $noGrpMsg
    if (-not $targetGroup) { $errCount.Value += $devices.Count; return }

    Write-Log "Adding $($devices.Count) device(s) to group '$($targetGroup.DisplayName)'..."

    foreach ($dev in $devices) {
        try {
            if (-not $dev.AadDeviceId) {
                Write-Log "SKIP '$($dev.Serial)' — no Azure AD Device ID" "Warning"
                $errCount.Value++
            }
            else {
                $body = '{"@odata.id":"https://graph.microsoft.com/v1.0/directoryObjects/' + $dev.AadDeviceId + '"}'
                Invoke-MgGraphRequest `
                    -Uri "https://graph.microsoft.com/v1.0/groups/$($targetGroup.Id)/members/`$ref" `
                    -Method POST -Body $body -ContentType "application/json" -ErrorAction Stop
                Write-Log "OK  '$($dev.Serial)' → '$($targetGroup.DisplayName)'" "Success"
                $okCount.Value++
            }
        }
        catch {
            $errMsg = $_.Exception.Message
            if ($errMsg -match "already exist|One or more added object references already exist") {
                Write-Log "SKIP '$($dev.Serial)' — already in group" "Warning"
                $okCount.Value++
            }
            else {
                Write-Log "FAIL '$($dev.Serial)': $errMsg" "Error"
                $errCount.Value++
            }
        }
        $ep_progressBar.Value++
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# BUILD FORM — Enrollment Profile (device-first layout)
# LEFT: devices list   RIGHT: profile tree
# ─────────────────────────────────────────────────────────────────────────────

$ep_form             = New-Object System.Windows.Forms.Form
$ep_form.Text        = "Intune — Enrollment Profile Assignment"
$ep_form.Size        = New-Object System.Drawing.Size(1300, 860)
$ep_form.StartPosition = "CenterScreen"
$ep_form.MinimumSize = New-Object System.Drawing.Size(1000, 700)
$ep_form.Font        = New-Object System.Drawing.Font("Segoe UI", 9)

# ── Header ───────────────────────────────────────────────────────────────────
$ep_headerPanel           = New-Object System.Windows.Forms.Panel
$ep_headerPanel.Dock      = "Top"
$ep_headerPanel.Height    = 52
$ep_headerPanel.BackColor = [System.Drawing.Color]::FromArgb(16, 124, 16)

$ep_connectBtn            = New-Object System.Windows.Forms.Button
$ep_connectBtn.Text       = "Connect to Graph"
$ep_connectBtn.Location   = New-Object System.Drawing.Point(10, 10)
$ep_connectBtn.Size       = New-Object System.Drawing.Size(155, 32)
$ep_connectBtn.BackColor  = [System.Drawing.Color]::White
$ep_connectBtn.FlatStyle  = "Flat"
$ep_connectBtn.Font       = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$ep_connectBtn.Add_Click({ Invoke-EPConnect })
$ep_headerPanel.Controls.Add($ep_connectBtn)

$ep_statusLbl             = New-Object System.Windows.Forms.Label
$ep_statusLbl.Text        = "Not connected — click 'Connect to Graph' to begin"
$ep_statusLbl.ForeColor   = [System.Drawing.Color]::LightYellow
$ep_statusLbl.Location    = New-Object System.Drawing.Point(178, 17)
$ep_statusLbl.Size        = New-Object System.Drawing.Size(760, 20)
$ep_statusLbl.Font        = New-Object System.Drawing.Font("Segoe UI", 9)
$ep_headerPanel.Controls.Add($ep_statusLbl)

$ep_modeLbl               = New-Object System.Windows.Forms.Label
$ep_modeLbl.Text          = "MODE: ENROLLMENT PROFILES"
$ep_modeLbl.ForeColor     = [System.Drawing.Color]::White
$ep_modeLbl.Font          = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$ep_modeLbl.Location      = New-Object System.Drawing.Point(950, 18)
$ep_modeLbl.Size          = New-Object System.Drawing.Size(305, 18)
$ep_modeLbl.TextAlign     = [System.Drawing.ContentAlignment]::MiddleRight
$ep_headerPanel.Controls.Add($ep_modeLbl)

# ── Log panel (bottom) ───────────────────────────────────────────────────────
$ep_logPanel              = New-Object System.Windows.Forms.Panel
$ep_logPanel.Dock         = "Bottom"
$ep_logPanel.Height       = 160
$ep_logPanel.BackColor    = [System.Drawing.Color]::FromArgb(240, 240, 240)

$ep_logTitleLbl           = New-Object System.Windows.Forms.Label
$ep_logTitleLbl.Text      = "  Activity Log"
$ep_logTitleLbl.Dock      = "Top"
$ep_logTitleLbl.Height    = 22
$ep_logTitleLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$ep_logTitleLbl.BackColor = [System.Drawing.Color]::FromArgb(225, 225, 225)

$ep_logBox                = New-Object System.Windows.Forms.RichTextBox
$ep_logBox.Dock           = "Fill"
$ep_logBox.ReadOnly       = $true
$ep_logBox.Font           = New-Object System.Drawing.Font("Consolas", 8.5)
$ep_logBox.BackColor      = [System.Drawing.Color]::FromArgb(252, 252, 252)
$ep_logBox.BorderStyle    = "None"

$ep_logPanel.Controls.Add($ep_logBox)       # Fill — first
$ep_logPanel.Controls.Add($ep_logTitleLbl)  # Top  — last
$script:LogBox = $ep_logBox

# ── Main split: LEFT = devices | RIGHT = profile tree ────────────────────────
$ep_split             = New-Object System.Windows.Forms.SplitContainer
$ep_split.Dock        = "Fill"
$ep_split.Orientation = "Vertical"
$ep_form.Add_Load({
    $ep_split.Panel1MinSize    = 540
    $ep_split.Panel2MinSize    = 280
    $ep_split.SplitterDistance = [int]($ep_form.ClientSize.Width * 0.62)
})

# ══════════════════════════════════════════════════════════════════════════════
# LEFT — Devices
# ══════════════════════════════════════════════════════════════════════════════
$ep_devGroup      = New-Object System.Windows.Forms.GroupBox
$ep_devGroup.Text = "ADE / ABM Devices"
$ep_devGroup.Dock = "Fill"

# Controls strip
$ep_devCtrl        = New-Object System.Windows.Forms.Panel
$ep_devCtrl.Dock   = "Top"
$ep_devCtrl.Height = 78

$ep_devSearchBox                 = New-Object System.Windows.Forms.TextBox
$ep_devSearchBox.PlaceholderText = "Search by serial or model..."
$ep_devSearchBox.Location        = New-Object System.Drawing.Point(8, 8)
$ep_devSearchBox.Size            = New-Object System.Drawing.Size(260, 24)
$ep_devSearchBox.Add_TextChanged({ Update-EPDeviceGrid })
$ep_devCtrl.Controls.Add($ep_devSearchBox)

$ep_typeCombo             = New-Object System.Windows.Forms.ComboBox
$ep_typeCombo.Location    = New-Object System.Drawing.Point(278, 8)
$ep_typeCombo.Size        = New-Object System.Drawing.Size(140, 24)
$ep_typeCombo.DropDownStyle = "DropDownList"
[void]$ep_typeCombo.Items.AddRange(@("All Types","iOS","iPadOS","macOS","Apple"))
$ep_typeCombo.SelectedIndex = 0
$ep_typeCombo.Add_SelectedIndexChanged({ Update-EPDeviceGrid })
$ep_devCtrl.Controls.Add($ep_typeCombo)

$ep_loadDevBtn          = New-Object System.Windows.Forms.Button
$ep_loadDevBtn.Text     = "Load Devices"
$ep_loadDevBtn.Location = New-Object System.Drawing.Point(428, 7)
$ep_loadDevBtn.Size     = New-Object System.Drawing.Size(100, 26)
$ep_loadDevBtn.Add_Click({ Get-EPAllDevices })
$ep_devCtrl.Controls.Add($ep_loadDevBtn)

$ep_selAllDevBtn          = New-Object System.Windows.Forms.Button
$ep_selAllDevBtn.Text     = "Select All"
$ep_selAllDevBtn.Location = New-Object System.Drawing.Point(8, 40)
$ep_selAllDevBtn.Size     = New-Object System.Drawing.Size(82, 26)
$ep_selAllDevBtn.Add_Click({
    foreach ($row in $ep_devGrid.Rows) { $row.Cells["EP_ColCheck"].Value = $true }
    $ep_assignBtn.Enabled = ($null -ne $script:EP_SelectedProfile)
})
$ep_devCtrl.Controls.Add($ep_selAllDevBtn)

$ep_clrAllDevBtn          = New-Object System.Windows.Forms.Button
$ep_clrAllDevBtn.Text     = "Clear All"
$ep_clrAllDevBtn.Location = New-Object System.Drawing.Point(96, 40)
$ep_clrAllDevBtn.Size     = New-Object System.Drawing.Size(82, 26)
$ep_clrAllDevBtn.Add_Click({
    foreach ($row in $ep_devGrid.Rows) { $row.Cells["EP_ColCheck"].Value = $false }
    $ep_assignBtn.Enabled = $false
})
$ep_devCtrl.Controls.Add($ep_clrAllDevBtn)

$ep_devCountLbl           = New-Object System.Windows.Forms.Label
$ep_devCountLbl.Text      = "No devices loaded — click 'Load Devices' after connecting"
$ep_devCountLbl.Location  = New-Object System.Drawing.Point(190, 46)
$ep_devCountLbl.Size      = New-Object System.Drawing.Size(380, 18)
$ep_devCountLbl.ForeColor = [System.Drawing.Color]::Gray
$ep_devCtrl.Controls.Add($ep_devCountLbl)

# Device DataGridView
$ep_devGrid                     = New-Object System.Windows.Forms.DataGridView
$ep_devGrid.Dock                = "Fill"
$ep_devGrid.AllowUserToAddRows  = $false
$ep_devGrid.AllowUserToDeleteRows = $false
$ep_devGrid.ReadOnly            = $false
$ep_devGrid.SelectionMode       = "FullRowSelect"
$ep_devGrid.MultiSelect         = $false
$ep_devGrid.RowHeadersVisible   = $false
$ep_devGrid.AutoSizeColumnsMode = "Fill"
$ep_devGrid.BackgroundColor     = [System.Drawing.Color]::White
$ep_devGrid.BorderStyle         = "None"
$ep_devGrid.GridColor           = [System.Drawing.Color]::FromArgb(220, 220, 220)
$ep_devGrid.CellBorderStyle     = "SingleHorizontal"
$ep_devGrid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 252)
$ep_devGrid.RowTemplate.Height  = 24

$ep_devGrid.Add_CellClick({
    param($s, $e)
    if ($e.RowIndex -ge 0 -and $e.ColumnIndex -ne 0) {
        $cur = $ep_devGrid.Rows[$e.RowIndex].Cells["EP_ColCheck"].Value
        $ep_devGrid.Rows[$e.RowIndex].Cells["EP_ColCheck"].Value = -not $cur
    }
})
$ep_devGrid.Add_CellValueChanged({
    param($s, $e)
    if ($e.ColumnIndex -eq 0) {
        $anyChecked = ($ep_devGrid.Rows | Where-Object { $_.Cells["EP_ColCheck"].Value -eq $true }).Count -gt 0
        $ep_assignBtn.Enabled = ($anyChecked -and $null -ne $script:EP_SelectedProfile)
    }
})
$ep_devGrid.Add_CurrentCellDirtyStateChanged({
    if ($ep_devGrid.IsCurrentCellDirty) { $ep_devGrid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) }
})

$ep_colChk              = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$ep_colChk.Name         = "EP_ColCheck"
$ep_colChk.HeaderText   = ""
$ep_colChk.Width        = 35
$ep_colChk.AutoSizeMode = "None"
[void]$ep_devGrid.Columns.Add($ep_colChk)

$ep_colSerial            = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$ep_colSerial.Name       = "EP_ColSerial"
$ep_colSerial.HeaderText = "Serial Number"
$ep_colSerial.ReadOnly   = $true
[void]$ep_devGrid.Columns.Add($ep_colSerial)

$ep_colModel             = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$ep_colModel.Name        = "EP_ColModel"
$ep_colModel.HeaderText  = "Model"
$ep_colModel.ReadOnly    = $true
[void]$ep_devGrid.Columns.Add($ep_colModel)

$ep_colOS                = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$ep_colOS.Name           = "EP_ColOS"
$ep_colOS.HeaderText     = "Type"
$ep_colOS.ReadOnly       = $true
$ep_colOS.Width          = 72
$ep_colOS.AutoSizeMode   = "None"
[void]$ep_devGrid.Columns.Add($ep_colOS)

$ep_colCurProfile            = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$ep_colCurProfile.Name       = "EP_ColCurProfile"
$ep_colCurProfile.HeaderText = "Current Profile"
$ep_colCurProfile.ReadOnly   = $true
$ep_colCurProfile.Width      = 200
$ep_colCurProfile.AutoSizeMode = "None"
[void]$ep_devGrid.Columns.Add($ep_colCurProfile)

$ep_colToken             = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$ep_colToken.Name        = "EP_ColToken"
$ep_colToken.HeaderText  = "ABM Token"
$ep_colToken.ReadOnly    = $true
$ep_colToken.Width       = 150
$ep_colToken.AutoSizeMode = "None"
[void]$ep_devGrid.Columns.Add($ep_colToken)

# Bottom strip inside left panel
$ep_bottomStrip          = New-Object System.Windows.Forms.Panel
$ep_bottomStrip.Dock     = "Bottom"
$ep_bottomStrip.Height   = 72

$ep_assignBtn            = New-Object System.Windows.Forms.Button
$ep_assignBtn.Text       = "ASSIGN SELECTED DEVICES TO PROFILE"
$ep_assignBtn.Location   = New-Object System.Drawing.Point(8, 8)
$ep_assignBtn.Size       = New-Object System.Drawing.Size(480, 36)
$ep_assignBtn.BackColor  = [System.Drawing.Color]::FromArgb(16, 124, 16)
$ep_assignBtn.ForeColor  = [System.Drawing.Color]::White
$ep_assignBtn.FlatStyle  = "Flat"
$ep_assignBtn.Font       = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$ep_assignBtn.Enabled    = $false
$ep_assignBtn.Add_Click({ Invoke-EPAssignment })
$ep_bottomStrip.Controls.Add($ep_assignBtn)

$ep_progressBar          = New-Object System.Windows.Forms.ProgressBar
$ep_progressBar.Location = New-Object System.Drawing.Point(8, 50)
$ep_progressBar.Size     = New-Object System.Drawing.Size(480, 16)
$ep_progressBar.Style    = "Continuous"
$ep_bottomStrip.Controls.Add($ep_progressBar)

$ep_devGroup.Controls.Add($ep_devGrid)       # Fill — first
$ep_devGroup.Controls.Add($ep_bottomStrip)   # Bottom
$ep_devGroup.Controls.Add($ep_devCtrl)       # Top  — last
$ep_split.Panel1.Controls.Add($ep_devGroup)

# ══════════════════════════════════════════════════════════════════════════════
# RIGHT — Enrollment Profile tree
# ══════════════════════════════════════════════════════════════════════════════
$ep_treeGroup      = New-Object System.Windows.Forms.GroupBox
$ep_treeGroup.Text = "Enrollment Profiles"
$ep_treeGroup.Dock = "Fill"

$ep_treeCtrlPanel        = New-Object System.Windows.Forms.Panel
$ep_treeCtrlPanel.Dock   = "Top"
$ep_treeCtrlPanel.Height = 62

$ep_refreshTreeBtn          = New-Object System.Windows.Forms.Button
$ep_refreshTreeBtn.Text     = "Refresh Tree"
$ep_refreshTreeBtn.Location = New-Object System.Drawing.Point(4, 5)
$ep_refreshTreeBtn.Size     = New-Object System.Drawing.Size(100, 26)
$ep_refreshTreeBtn.Add_Click({ Initialize-EPTree })
$ep_treeCtrlPanel.Controls.Add($ep_refreshTreeBtn)

# Label showing the currently selected profile
$ep_selProfLbl            = New-Object System.Windows.Forms.Label
$ep_selProfLbl.Text       = "No profile selected"
$ep_selProfLbl.Location   = New-Object System.Drawing.Point(4, 36)
$ep_selProfLbl.Size       = New-Object System.Drawing.Size(600, 20)
$ep_selProfLbl.Font       = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$ep_selProfLbl.ForeColor  = [System.Drawing.Color]::Gray
$ep_treeCtrlPanel.Controls.Add($ep_selProfLbl)

$ep_treeView               = New-Object System.Windows.Forms.TreeView
$ep_treeView.Dock          = "Fill"
$ep_treeView.Font          = New-Object System.Drawing.Font("Segoe UI", 9)
$ep_treeView.BorderStyle   = "None"
$ep_treeView.HideSelection = $false
$ep_treeView.Add_AfterSelect({
    param($s, $e)
    $node = $e.Node
    if ($node.Tag -and ($node.Tag -isnot [string])) {
        Select-EPProfile $node.Tag
    }
})

$ep_treeGroup.Controls.Add($ep_treeView)       # Fill — first
$ep_treeGroup.Controls.Add($ep_treeCtrlPanel)  # Top  — last
$ep_split.Panel2.Controls.Add($ep_treeGroup)

# ── Assemble form ─────────────────────────────────────────────────────────────
$ep_form.Controls.Add($ep_split)       # Fill — first
$ep_form.Controls.Add($ep_logPanel)    # Bottom
$ep_form.Controls.Add($ep_headerPanel) # Top — last

Write-Log "Intune Enrollment Profile Assignment Tool ready."
Write-Log "1. Click 'Connect to Graph'   2. Click 'Load Devices'   3. Select a profile from the tree   4. Check devices and click Assign"
[void]$ep_form.ShowDialog()

} # ── end Enrollment Profile mode ─────────────────────────────────────────────
