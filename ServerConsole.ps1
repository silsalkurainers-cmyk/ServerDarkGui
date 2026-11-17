param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'
$script:ServerHost = $null
$script:ServerProcess = $null
$script:CloseWhenStopped = $false

$processHostSource = @'
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;

public sealed class ServerConsoleProcessHost
{
    private readonly Process process;
    private readonly ConcurrentQueue<string> output;
    private readonly StreamWriter input;

    public Process Process { get { return process; } }
    public ConcurrentQueue<string> Output { get { return output; } }

    public ServerConsoleProcessHost(string batchPath)
    {
        output = new ConcurrentQueue<string>();
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = Environment.GetEnvironmentVariable("ComSpec");
        info.Arguments = "/d /c call \"" + batchPath + "\"";
        info.WorkingDirectory = Path.GetDirectoryName(batchPath);
        info.UseShellExecute = false;
        info.CreateNoWindow = false;
        info.WindowStyle = ProcessWindowStyle.Hidden;
        info.RedirectStandardInput = true;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;

        process = new Process();
        process.StartInfo = info;
        process.OutputDataReceived += (sender, args) => { if (args.Data != null) output.Enqueue(args.Data); };
        process.ErrorDataReceived += (sender, args) => { if (args.Data != null) output.Enqueue("[stderr] " + args.Data); };

        if (!process.Start())
            throw new InvalidOperationException("Windows could not start the server batch file.");

        input = process.StandardInput;
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
    }

    public void Send(string command)
    {
        input.WriteLine(command);
        input.Flush();
    }

    public void Dispose()
    {
        process.Dispose();
    }
}
'@
Add-Type -TypeDefinition $processHostSource -Language CSharp -ErrorAction Stop | Out-Null

function Start-RedirectedBatch {
    param([Parameter(Mandatory = $true)][string]$BatchPath)
    return [ServerConsoleProcessHost]::new($BatchPath)
}

function Receive-ProcessOutput {
    param(
        [Parameter(Mandatory = $true)][ServerConsoleProcessHost]$ProcessHost,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Destination
    )

    [string]$line = $null
    while ($ProcessHost.Output.TryDequeue([ref]$line)) {
        $Destination.Add($line)
        $line = $null
    }
}

if ($SelfTest) {
    $testFolder = Join-Path $env:TEMP ('ServerConsole-SmokeTest-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $testFolder -Force)
    $testBatch = Join-Path $testFolder 'run-server.bat'
    $nl = [Environment]::NewLine
    $testContent = '@echo off' + $nl +
        'echo SELFTEST-START' + $nl +
        'echo SELFTEST-SECOND' + $nl +
        'echo SELFTEST-STDERR 1>&2' + $nl +
        'set /p received=' + $nl +
        'if "%received%"=="PING" exit /b 0' + $nl +
        'exit /b 1' + $nl
    $testHost = $null
    try {
        [System.IO.File]::WriteAllText($testBatch, $testContent, [System.Text.Encoding]::ASCII)
        $testHost = Start-RedirectedBatch -BatchPath $testBatch
        $testProcess = $testHost.Process
        $capturedLines = New-Object 'System.Collections.Generic.List[string]'
        $testHost.Send('PING')
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while (-not $testProcess.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            Receive-ProcessOutput -ProcessHost $testHost -Destination $capturedLines
            Start-Sleep -Milliseconds 50
        }

        if (-not $testProcess.HasExited) {
            $testProcess.Kill()
            throw 'Smoke test timed out while waiting for the test server process.'
        }

        $testProcess.WaitForExit()
        Receive-ProcessOutput -ProcessHost $testHost -Destination $capturedLines
        $capturedText = $capturedLines -join [Environment]::NewLine

        if ($testProcess.ExitCode -ne 0 -or
            $capturedText -notmatch 'SELFTEST-START' -or
            $capturedText -notmatch 'SELFTEST-SECOND' -or
            $capturedText -notmatch 'SELFTEST-STDERR') {
            throw ('Smoke test failed. Exit code: ' + $testProcess.ExitCode + '. Output: ' + $capturedText)
        }

        Write-Output 'PASS: batch launch, stdout, stderr, and command input all work.'
        exit 0
    }
    catch {
        Write-Output ('SELFTEST ERROR: ' + $_.Exception.ToString())
        throw
    }
    finally {
        if ($null -ne $testHost) { $testHost.Dispose() }
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
        if ($null -eq $script:ServerHost -or $script:ServerHost.Process.HasExited) { return }
        if ([string]::IsNullOrWhiteSpace($CommandText)) { return }
        try {
            $script:ServerHost.Send($CommandText)
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
        $newLines = New-Object 'System.Collections.Generic.List[string]'
        if ($null -ne $script:ServerHost) {
            Receive-ProcessOutput -ProcessHost $script:ServerHost -Destination $newLines
        }
        foreach ($line in $newLines) {
            Add-LogLine -Message $line
        }

        if ($null -ne $script:ServerProcess -and $script:ServerProcess.HasExited) {
            $script:ServerProcess.WaitForExit()
            $finalLines = New-Object 'System.Collections.Generic.List[string]'
            Receive-ProcessOutput -ProcessHost $script:ServerHost -Destination $finalLines
            foreach ($line in $finalLines) { Add-LogLine -Message $line }
            $exitCode = $script:ServerProcess.ExitCode
            Add-LogLine ('[console] Server process exited with code ' + $exitCode + '.')
            $script:ServerHost.Dispose()
            $script:ServerHost = $null
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
            $script:ServerHost = Start-RedirectedBatch -BatchPath $serverBatch
            $script:ServerProcess = $script:ServerHost.Process
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