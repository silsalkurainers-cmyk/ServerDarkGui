param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'
$script:OutputQueue = $null

function Start-RedirectedBatch {
    param([Parameter(Mandatory = $true)][string]$BatchPath)
    $script:OutputQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = '/d /c ""' + $BatchPath + '""'
    $startInfo.WorkingDirectory = Split-Path -Parent $BatchPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $stdoutHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $eventArgs)
        if ($null -ne $eventArgs.Data) { [void]$script:OutputQueue.Enqueue($eventArgs.Data) }
    }
    $stderrHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $eventArgs)
        if ($null -ne $eventArgs.Data) { [void]$script:OutputQueue.Enqueue('[stderr] ' + $eventArgs.Data) }
    }
    $process.add_OutputDataReceived($stdoutHandler)
    $process.add_ErrorDataReceived($stderrHandler)
    if (-not $process.Start()) { throw 'Windows could not start the server batch file.' }
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
    return $process
}

if ($SelfTest) {
    $testFolder = Join-Path $env:TEMP ('ServerConsole-SmokeTest-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $testFolder -Force)
    Write-Output ('SELFTEST: folder=' + $testFolder)
    $testBatch = Join-Path $testFolder 'run-server.bat'
    $nl = [Environment]::NewLine
    $testContent = '@echo off' + $nl +
        'echo SELFTEST-START' + $nl +
        'set /p received=' + $nl +
        'echo SELFTEST-COMMAND:%received%' + $nl +
        'echo SELFTEST-STDERR 1>&2' + $nl +
        'exit /b 0' + $nl
    $testProcess = $null
    try {
        [System.IO.File]::WriteAllText($testBatch, $testContent, [System.Text.Encoding]::ASCII)
        $testProcess = Start-RedirectedBatch -BatchPath $testBatch
        Write-Output ('SELFTEST: started process ' + $testProcess.Id)
        $capturedLines = New-Object 'System.Collections.Generic.List[string]'
        $startSeen = $false
        $deadline = [DateTime]::UtcNow.AddSeconds(8)
        while (-not $startSeen -and [DateTime]::UtcNow -lt $deadline) {
            [string]$capturedLine = $null
            while ($script:OutputQueue.TryDequeue([ref]$capturedLine)) {
                $capturedLines.Add($capturedLine)
                if ($capturedLine -match 'SELFTEST-START') { $startSeen = $true }
                $capturedLine = $null
            }
            if ($testProcess.HasExited) {
                $testProcess.WaitForExit()
                throw ('Test batch exited before input with code ' + $testProcess.ExitCode + '. Output: ' + ($capturedLines -join [Environment]::NewLine))
            }
            if (-not $startSeen) { Start-Sleep -Milliseconds 50 }
        }
        if (-not $startSeen) {
            throw ('Test batch did not emit its start line. Output: ' + ($capturedLines -join [Environment]::NewLine))
        }
        $testProcess.StandardInput.WriteLine('PING')
        $testProcess.StandardInput.Flush()
        if (-not $testProcess.WaitForExit(15000)) {
            $testProcess.Kill()
            throw 'Smoke test timed out while waiting for the test server process.'
        }
        $testProcess.WaitForExit()
        Write-Output ('SELFTEST: process exit code ' + $testProcess.ExitCode)
        [string]$capturedLine = $null
        while ($script:OutputQueue.TryDequeue([ref]$capturedLine)) {
            $capturedLines.Add($capturedLine)
            $capturedLine = $null
        }
        $capturedText = $capturedLines -join [Environment]::NewLine
        Write-Output ('SELFTEST: captured output: ' + $capturedText)
        if ($capturedText -notmatch 'SELFTEST-START' -or
            $capturedText -notmatch 'SELFTEST-COMMAND:PING' -or
            $capturedText -notmatch 'SELFTEST-STDERR') {
            throw ('Smoke test did not receive expected output. Captured: ' + $capturedText)
        }
        Write-Output 'PASS: batch launch, stdout, stderr, and command input all work.'
        exit 0
    }
    catch {
        Write-Output ('SELFTEST ERROR: ' + $_.Exception.ToString())
        throw
    }
    finally {
        if ($null -ne $testProcess) { $testProcess.Dispose() }
        Remove-Item -LiteralPath $testFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

    $root = Split-Path -Parent $MyInvocation.MyCommand.Path
    $serverBatch = Join-Path $root 'run-server.bat'
    if (-not (Test-Path -LiteralPath $serverBatch -PathType Leaf)) {
        $message = 'The original server launcher was not found.' + [Environment]::NewLine + [Environment]::NewLine +
            'Run INSTALL.bat in your server folder first. It preserves your original launcher as run-server.bat.'
        [System.Windows.Forms.MessageBox]::Show(
            $message, 'Server Console - Setup Required',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        exit 1
    }

    $script:ServerProcess = $null
    $script:CloseWhenStopped = $false
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Minecraft Server Console'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(1050, 720)
    $form.MinimumSize = New-Object System.Drawing.Size(720, 460)
    $form.BackColor = [System.Drawing.Color]::FromArgb(10, 12, 14)
    $form.ForeColor = [System.Drawing.Color]::FromArgb(100, 255, 130)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.KeyPreview = $true

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = [System.Windows.Forms.DockStyle]::Top
    $header.Height = 58
    $header.BackColor = [System.Drawing.Color]::FromArgb(17, 20, 22)
    $header.Padding = New-Object System.Windows.Forms.Padding(16, 8, 12, 8)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'MINECRAFT SERVER'
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(16, 9)
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(100, 255, 130)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = 'LIVE SERVER OUTPUT'
    $subtitle.AutoSize = $true
    $subtitle.Location = New-Object System.Drawing.Point(18, 32)
    $subtitle.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $subtitle.ForeColor = [System.Drawing.Color]::FromArgb(125, 145, 132)

    $status = New-Object System.Windows.Forms.Label
    $status.Text = 'STARTING'
    $status.AutoSize = $true
    $status.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $status.Location = New-Object System.Drawing.Point(820, 20)
    $status.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $status.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 90)

    $actions = New-Object System.Windows.Forms.FlowLayoutPanel
    $actions.Dock = [System.Windows.Forms.DockStyle]::Right
    $actions.Width = 205
    $actions.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $actions.WrapContents = $false
    $actions.BackColor = [System.Drawing.Color]::Transparent

    $stopButton = New-Object System.Windows.Forms.Button
    $stopButton.Text = 'STOP SERVER'
    $stopButton.Width = 112
    $stopButton.Height = 32
    $stopButton.Margin = New-Object System.Windows.Forms.Padding(6, 4, 0, 0)
    $stopButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $stopButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 105, 78)
    $stopButton.BackColor = [System.Drawing.Color]::FromArgb(25, 42, 30)
    $stopButton.ForeColor = [System.Drawing.Color]::FromArgb(115, 255, 145)

    $clearButton = New-Object System.Windows.Forms.Button
    $clearButton.Text = 'CLEAR'
    $clearButton.Width = 72
    $clearButton.Height = 32
    $clearButton.Margin = New-Object System.Windows.Forms.Padding(6, 4, 0, 0)
    $clearButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $clearButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(55, 65, 60)
    $clearButton.BackColor = [System.Drawing.Color]::FromArgb(28, 31, 32)
    $clearButton.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 184)

    [void]$actions.Controls.Add($stopButton)
    [void]$actions.Controls.Add($clearButton)
    [void]$header.Controls.Add($title)
    [void]$header.Controls.Add($subtitle)
    [void]$header.Controls.Add($status)
    [void]$header.Controls.Add($actions)

    $log = New-Object System.Windows.Forms.RichTextBox
    $log.Dock = [System.Windows.Forms.DockStyle]::Fill
    $log.ReadOnly = $true
    $log.DetectUrls = $false
    $log.WordWrap = $false
    $log.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $log.BackColor = [System.Drawing.Color]::FromArgb(8, 10, 11)
    $log.ForeColor = [System.Drawing.Color]::FromArgb(110, 245, 135)
    $log.Font = New-Object System.Drawing.Font('Consolas', 10)
    $log.HideSelection = $false

    $footer = New-Object System.Windows.Forms.Panel
    $footer.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $footer.Height = 58
    $footer.BackColor = [System.Drawing.Color]::FromArgb(17, 20, 22)
    $footer.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 10)

    $sendButton = New-Object System.Windows.Forms.Button
    $sendButton.Text = 'SEND'
    $sendButton.Dock = [System.Windows.Forms.DockStyle]::Right
    $sendButton.Width = 92
    $sendButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $sendButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 105, 78)
    $sendButton.BackColor = [System.Drawing.Color]::FromArgb(25, 42, 30)
    $sendButton.ForeColor = [System.Drawing.Color]::FromArgb(115, 255, 145)

    $commandBox = New-Object System.Windows.Forms.TextBox
    $commandBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $commandBox.BackColor = [System.Drawing.Color]::FromArgb(28, 32, 33)
    $commandBox.ForeColor = [System.Drawing.Color]::FromArgb(220, 235, 224)
    $commandBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $commandBox.Font = New-Object System.Drawing.Font('Consolas', 10)

    [void]$footer.Controls.Add($commandBox)
    [void]$footer.Controls.Add($sendButton)
    [void]$form.Controls.Add($log)
    [void]$form.Controls.Add($footer)
    [void]$form.Controls.Add($header)

    function Add-LogLine {
        param([string]$Message)
        if ($log.IsDisposed) { return }
        if ($log.TextLength -gt 900000) {
            $log.Select(0, 180000)
            $log.SelectedText = ''
        }
        $log.AppendText($Message + [Environment]::NewLine)
        $log.SelectionStart = $log.TextLength
        $log.ScrollToCaret()
    }

    function Set-ConsoleStatus {
        param([string]$Message, [System.Drawing.Color]$Color)
        $status.Text = $Message
        $status.ForeColor = $Color
    }

    function Send-ServerCommand {
        param([string]$CommandText)
        if ($null -eq $script:ServerProcess -or $script:ServerProcess.HasExited) { return }
        if ([string]::IsNullOrWhiteSpace($CommandText)) { return }
        try {
            $script:ServerProcess.StandardInput.WriteLine($CommandText)
            $script:ServerProcess.StandardInput.Flush()
            Add-LogLine ('> ' + $CommandText)
            $commandBox.Clear()
        }
        catch {
            Add-LogLine ('[input error] ' + $_.Exception.Message)
        }
    }

    $sendButton.Add_Click({ Send-ServerCommand -CommandText $commandBox.Text })
    $commandBox.Add_KeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $eventArgs.SuppressKeyPress = $true
            Send-ServerCommand -CommandText $commandBox.Text
        }
    })
    $clearButton.Add_Click({ $log.Clear() })
    $stopButton.Add_Click({
        Send-ServerCommand -CommandText 'stop'
        Set-ConsoleStatus -Message 'STOP REQUESTED' -Color ([System.Drawing.Color]::FromArgb(255, 205, 90))
        $stopButton.Enabled = $false
    })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 100
    $timer.Add_Tick({
        if ($null -ne $script:OutputQueue) {
            [string]$line = $null
            while ($script:OutputQueue.TryDequeue([ref]$line)) {
                Add-LogLine -Message $line
                $line = $null
            }
        }
        if ($null -ne $script:ServerProcess -and $script:ServerProcess.HasExited) {
            $script:ServerProcess.WaitForExit()
            [string]$line = $null
            while ($script:OutputQueue.TryDequeue([ref]$line)) {
                Add-LogLine -Message $line
                $line = $null
            }
            $exitCode = $script:ServerProcess.ExitCode
            Add-LogLine ('[console] Server process exited with code ' + $exitCode + '.')
            $script:ServerProcess.Dispose()
            $script:ServerProcess = $null
            $timer.Stop()
            $commandBox.Enabled = $false
            $sendButton.Enabled = $false
            $stopButton.Enabled = $false
            Set-ConsoleStatus -Message 'STOPPED' -Color ([System.Drawing.Color]::FromArgb(145, 155, 150))
            if ($script:CloseWhenStopped) {
                $form.BeginInvoke([System.Action]{ $form.Close() }) | Out-Null
            }
        }
    })

    $form.Add_Shown({
        Add-LogLine 'Server Dark Console'
        Add-LogLine ('Working directory: ' + $root)
        Add-LogLine 'Starting your original run-server.bat...'
        try {
            $script:ServerProcess = Start-RedirectedBatch -BatchPath $serverBatch
            Set-ConsoleStatus -Message 'RUNNING' -Color ([System.Drawing.Color]::FromArgb(100, 255, 130))
            $timer.Start()
            $commandBox.Focus()
        }
        catch {
            Add-LogLine ('[startup error] ' + $_.Exception.Message)
            Set-ConsoleStatus -Message 'FAILED TO START' -Color ([System.Drawing.Color]::FromArgb(255, 110, 110))
            $commandBox.Enabled = $false
            $sendButton.Enabled = $false
            $stopButton.Enabled = $false
        }
    })

    $form.Add_FormClosing({
        param($sender, $eventArgs)
        if ($null -ne $script:ServerProcess -and -not $script:ServerProcess.HasExited) {
            $choice = [System.Windows.Forms.MessageBox]::Show(
                "The server is still running. Send the stop command and close this window after the server shuts down?",
                'Server Still Running',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
                Send-ServerCommand -CommandText 'stop'
                $script:CloseWhenStopped = $true
                Set-ConsoleStatus -Message 'STOPPING' -Color ([System.Drawing.Color]::FromArgb(255, 205, 90))
            }
            $eventArgs.Cancel = $true
        }
    })

    [void]$form.ShowDialog()
}
catch {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.ToString(), 'Server Console Error',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {
        Write-Error $_
    }
    exit 1
}