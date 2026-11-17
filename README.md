# Server Dark Console

A standalone dark Minecraft server console window for Windows. It is not a Minecraft mod and does not use a JAR.

When you double-click **run.bat** after installation, it opens a dark window with green server output, a command input box, a Send button, and a Stop Server button.

## What it does

- Starts your existing server launcher, preserving its Java command, memory settings, Fabric arguments, and other options.
- Shows live standard output and error output in a dark window.
- Lets you type Minecraft server commands and send them to the running server.
- Sends the normal stop command when you press Stop Server.
- Keeps the original launcher backed up as **run-server.bat**.
- Does not patch Minecraft, install a mod, or change server files.

## Install

1. Download **server-console-package.zip** from the latest GitHub Release.
2. Extract the ZIP directly into the same folder as your current server **run.bat**. Do not extract it into a separate subfolder.
3. Double-click **INSTALL.bat** once and let it finish.
4. Double-click the new **run.bat** whenever you want to start the server.

The installer renames your original launcher to **run-server.bat** and installs a small wrapper as the new **run.bat**. The console runs **run-server.bat** from the server directory, so relative paths and your existing server files remain in place.

To restore the original launcher, close the server and run **RESTORE-ORIGINAL-RUN.bat**.

## Requirements

- Windows 10 or Windows 11.
- Windows PowerShell 5.1 and the Windows .NET Framework components already included with Windows.
- Java, as already required by your Minecraft server.

There is no Gradle, Maven, JDK, Fabric dependency, third-party library, or separate application runtime to install. The console itself is a PowerShell/Windows Forms script using built-in Windows components. Java is still required to run Minecraft.

## Verification

The GitHub Actions workflow checks the PowerShell script syntax and runs a Windows smoke test that launches a test batch file, captures stdout and stderr, and sends a command through standard input. This verifies the process-connection layer used by the console. It cannot replace testing on your exact server folder and server startup script.
