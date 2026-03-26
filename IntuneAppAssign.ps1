#Requires -Version 5.1
<#
.SYNOPSIS
    Intune Bulk App Assignment Tool - Interactive GUI
.DESCRIPTION
    Select multiple apps, choose an assignment intent (Required / Available / Uninstall),
    pick one or more Azure AD groups, and bulk-assign in a single click.
.NOTES
    Requires: Microsoft.Graph PowerShell module
    Install:  Install-Module Microsoft.Graph -Scope CurrentUser
    Scopes:   DeviceManagementApps.ReadWrite.All, Group.Read.All
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ─────────────────────────────────────────────────────────────────────────────
# Module check — before building the form
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
# Script-level state
# ─────────────────────────────────────────────────────────────────────────────
$script:Apps             = [System.Collections.Generic.List[PSObject]]::new()
$script:Groups           = [System.Collections.Generic.List[PSObject]]::new()
$script:SelectedGroupIds = [System.Collections.Generic.HashSet[string]]::new()

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

function Write-Log {
    param([string]$Message, [string]$Level = "Info")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "Success" { [System.Drawing.Color]::DarkGreen }
        "Error"   { [System.Drawing.Color]::Crimson }
        "Warning" { [System.Drawing.Color]::DarkOrange }
        default   { [System.Drawing.Color]::Black }
    }
    $logBox.SelectionStart  = $logBox.TextLength
    $logBox.SelectionLength = 0
    $logBox.SelectionColor  = $color
    $logBox.AppendText("[$timestamp] $Message`r`n")
    $logBox.ScrollToCaret()
}

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
                # 400/409 = assignment already exists for this target/intent
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
# BUILD FORM
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
# Add logBox FIRST (front z-order, processed last = gets Fill of remaining space)
# Add logTitleLabel SECOND (back z-order, processed first = carves Top 22px)
$logPanel.Controls.Add($logBox)
$logPanel.Controls.Add($logTitleLabel)

# ── Main split (apps | config) ───────────────────────────────────────────────
$splitMain             = New-Object System.Windows.Forms.SplitContainer
$splitMain.Dock        = "Fill"
$splitMain.Orientation = "Vertical"
# Min sizes and splitter distance must be set after the form has a real width
$form.Add_Load({
    $splitMain.Panel1MinSize    = 480
    $splitMain.Panel2MinSize    = 340
    $splitMain.SplitterDistance = [int]($form.ClientSize.Width * 0.60)
})

# ────────────────────────────────────────────────────────────────────────────
# LEFT — Apps
# ────────────────────────────────────────────────────────────────────────────
$appsGroupBox      = New-Object System.Windows.Forms.GroupBox
$appsGroupBox.Text = "Apps"
$appsGroupBox.Dock = "Fill"

# Controls strip (search, filter, buttons)
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

# DataGridView
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

# Clicking any cell in a row toggles the checkbox
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

# ────────────────────────────────────────────────────────────────────────────
# RIGHT — Intent + Groups + Action
# ────────────────────────────────────────────────────────────────────────────
$rightLayout              = New-Object System.Windows.Forms.TableLayoutPanel
$rightLayout.Dock         = "Fill"
$rightLayout.ColumnCount  = 1
$rightLayout.RowCount     = 5
$rightLayout.Padding      = New-Object System.Windows.Forms.Padding(6, 4, 6, 4)

# Row heights: intent fixed | special targets fixed | groups flexible | button fixed | progress fixed
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

# ── Intent ────────────────────────────────────────────────────────────────────
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

# Disable All Devices when Available is selected (Intune doesn't support it)
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

# ── Special Targets ───────────────────────────────────────────────────────────
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
$chkAllDevices.Enabled = $false   # Available is the default intent; re-enabled when Required/Uninstall is chosen

$rightLayout.Controls.Add($specialGroup, 0, 1)

# ── Groups ────────────────────────────────────────────────────────────────────
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

# ── Assign button ─────────────────────────────────────────────────────────────
$assignButton           = New-Object System.Windows.Forms.Button
$assignButton.Text      = "ASSIGN APPS TO SELECTED GROUPS"
$assignButton.Dock      = "Fill"
$assignButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$assignButton.ForeColor = [System.Drawing.Color]::White
$assignButton.FlatStyle = "Flat"
$assignButton.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$assignButton.Add_Click({ Start-Assignment })
$rightLayout.Controls.Add($assignButton, 0, 3)

# ── Progress bar ──────────────────────────────────────────────────────────────
$progressBar        = New-Object System.Windows.Forms.ProgressBar
$progressBar.Dock   = "Fill"
$progressBar.Style  = "Continuous"
$rightLayout.Controls.Add($progressBar, 0, 4)

$splitMain.Panel2.Controls.Add($rightLayout)

# ── Assemble form (order matters for Dock layout) ────────────────────────────
$form.Controls.Add($splitMain)    # Fill — added first so it gets remaining space
$form.Controls.Add($logPanel)     # Bottom
$form.Controls.Add($headerPanel)  # Top

# ─────────────────────────────────────────────────────────────────────────────
# LAUNCH
# ─────────────────────────────────────────────────────────────────────────────
Write-Log "Intune Bulk App Assignment Tool ready."
Write-Log "Required module: Microsoft.Graph  |  Install: Install-Module Microsoft.Graph -Scope CurrentUser"
[void]$form.ShowDialog()
