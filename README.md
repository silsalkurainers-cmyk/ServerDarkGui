# Server Dark GUI

A server-side Fabric mod that themes Minecraft's built-in dedicated-server Swing window with near-black panels and green text.

## What it changes

- Near-black backgrounds for the built-in server window.
- Green text, selection colors, labels, and controls.
- A best-effort recolor of the built-in statistics graph.
- Keeps Minecraft's existing Stats, Players, and Log/chat interface.

This changes the actual Minecraft server window. It does not recolor the Command Prompt or terminal.

## Requirements

- Minecraft Java Edition **26.2**
- Fabric Loader **0.19.3 or newer**
- Java **25 or newer** to run the server
- The normal server GUI must be enabled. Do not start the server with the `nogui` argument.

## Install

1. Install Fabric on the Minecraft 26.2 dedicated server.
2. Put `server-dark-gui-1.0.0.jar` in the server's `mods` folder.
3. Start the server without `nogui`.

## Build on Windows

A JDK **21 or newer** is required. Open the project folder in Command Prompt and run:

```cmd
BUILD-WINDOWS.bat
```

The script uses only the JDK's `javac` and `jar` tools plus Windows PowerShell to download the compile-time Mixin API. No Gradle, Maven build tool, or wrapper is used.

The output is:

```
build\server-dark-gui-1.0.0.jar
```

## Automatic GitHub build

Every push to `main` runs the same direct Java compilation in GitHub Actions. The resulting JAR is attached to the workflow run as an artifact. Pushing a version tag such as `v1.0.0` also publishes a GitHub Release containing the JAR.

## Compatibility note

The build checks that the Java source compiles and packages correctly. The mixin hooks still need to be tested in an actual Minecraft 26.2 Fabric dedicated-server session.
