# Cage Brawlers — Running Guide

This guide explains how to run the project locally in **server mode** and in **client mode**, using either the Godot Editor or exported binaries.

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Godot 4.5** (or later 4.x) | Must match the version in `project.godot` (`config/features` lists `"4.5"`). Download from [godotengine.org](https://godotengine.org/download). |
| **Two terminal windows** | One for the server process, one for the client (or use the Editor for the client). |
| **Firewall** | Port **7777 UDP** must be open on localhost (default; no changes needed for local testing). |

---

## Quick-Start (local machine, two terminals)

### Terminal 1 — Start the server

```bash
# Linux / macOS
./godot --headless --path /path/to/Cage-Brawlers

# Windows (PowerShell)
.\godot.exe --headless --path C:\path\to\Cage-Brawlers
```

`--headless` tells the engine to start without a display window. The engine detects this automatically (`DisplayServer.get_name() == "headless"`) and boots into server mode.

Expected output:
```
[SERVER] Starting dedicated server on port 7777…
[SERVER] Listening. Waiting for a client…
```

### Terminal 2 (or Godot Editor) — Start the client

**Option A — from the command line:**
```bash
# Linux / macOS
./godot --path /path/to/Cage-Brawlers

# Windows (PowerShell)
.\godot.exe --path C:\path\to\Cage-Brawlers
```

**Option B — from the Godot Editor:**
Open the project in the editor and press **F5** (or click the ▶ Play button). The editor boots a display window which the game treats as a client.

Expected output in the server terminal once the client connects:
```
[SERVER] Client 1 connected — starting test match.
[SERVER] Match started!
```

The client window shows the 8×8 test map with both teams placed and ready to play.

---

## Explicit `--server` flag (alternative to `--headless`)

If you need to run the server *with* a display (e.g. on Windows where `--headless` still opens a window), pass `--server` as a custom argument **after** a `--` separator:

```bash
# Linux / macOS
./godot --path /path/to/Cage-Brawlers -- --server

# Windows (PowerShell)
.\godot.exe --path C:\path\to\Cage-Brawlers -- --server
```

The `--` separator tells Godot to stop processing its own flags; everything after it lands in `OS.get_cmdline_args()` where `Main.gd` looks for `--server`.

---

## Server map selection (compiled map files)

The server now loads map files from `res://resources/maps/*.json`.

- While the server is waiting for clients, it prints a numbered map list in the terminal.
- Type the number and press **Enter** to change the selected map before both rosters are received.
- The currently selected map is the one loaded for the next battle.
- If interactive stdin is not available, the server keeps the default/CLI selection.

Example terminal output:

```text
[SERVER] Available maps:
   * 1) default_map.json
      2) custom_map.json
[SERVER] Type a map number and press Enter to select it before both rosters are received.
```

- Default map path is `res://resources/maps/default_map.json`.
- You can override from CLI at startup:

```bash
# Linux / macOS
./godot --headless --path /path/to/Cage-Brawlers -- --map=default_map.json

# Windows (PowerShell)
.\godot.exe --headless --path C:\path\to\Cage-Brawlers -- --map=default_map.json
```

You can also pass a full resource path:

```bash
--map=res://resources/maps/default_map.json
```

If a selected map fails to load, the server falls back to the built-in test map.

---

## Standalone map editor app

Map authoring is no longer part of the gameplay client lobby.
Use the dedicated map editor scene:

```bash
# Linux / macOS
./godot --path /path/to/Cage-Brawlers --scene res://scenes/MapEditor.tscn

# Windows (PowerShell)
.\godot.exe --path C:\Users\tiago\Documents\GitHub\Cage-Brawlers --scene res://scenes/MapEditor.tscn
```

By default, it saves to:

- `res://resources/maps/custom_map.json`

You can then run the server with:

- `--map=custom_map.json`

For exported workflows, create a separate export preset using `scenes/MapEditor.tscn` as the main scene.

---

## Exported binaries

After exporting the project (**Project → Export…** in the editor):

### Server binary

```bash
# Linux dedicated-server export
./cage_brawlers_server

# Windows server export
.\cage_brawlers_server.exe
```

A **dedicated server export template** (Linux is the typical target) automatically sets the `dedicated_server` feature flag, which `Main.gd` checks first — no extra arguments needed.

### Client binary

```bash
# Linux
./cage_brawlers

# Windows
.\cage_brawlers.exe
```

---

## Connecting to a remote server

By default the client hard-codes `127.0.0.1` (see `Main.gd → _boot_client`). To connect to a remote host:

1. Open `scripts/Main.gd`.
2. Change the address in `_boot_client`:
   ```gdscript
   var err: Error = NetworkManager.create_client("YOUR_SERVER_IP", NetworkManager.DEFAULT_PORT)
   ```
3. Make sure **UDP port 7777** is forwarded on the remote machine.

---

## Port and player-count configuration

Both constants live in `scripts/autoloads/NetworkManager.gd`:

```gdscript
const DEFAULT_PORT: int = 7777   # Change to any free UDP port.
const MAX_CLIENTS: int = 2       # Maximum simultaneous connections.
```

Restart both the server and client after any change.

---

## What you see in the test match

| Element | Meaning |
|---|---|
| **Blue rectangles** (left side) | Team A characters |
| **Red rectangles** (right side) | Team B characters |
| **Yellow ring** | Currently active character |
| **Gray square + X** | Knocked-down character |
| **Black square** | Dead character |
| **Dark brown thick line** | Wall (blocks movement, sight, ranged) |
| **Gold thick line** | Barricade (crouching cover, blocks ranged if crouched) |
| **HP bars** (3 segments per character) | Current health; darkened segment = permanently disabled |

### Controls

Actions are submitted through the right-side HUD panel. The available buttons change with the active phase:

| Phase | Available buttons |
|---|---|
| **Beginning** | Skip · Move… · Stand Up · End Turn |
| **Pending Rotation** | 3×3 compass (N / NE / E / SE / S / SW / W / NW) |
| **Main** | Attack… · Skip Main · End Turn |
| **Ending** | Crouch · Stand Up · End Turn |

**Move…** and **Attack…** enter a selection mode — click a tile (move) or an enemy character (attack) on the map to confirm, or press **Cancel** to abort.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Client shows "Waiting for server…" indefinitely | Server not running, or wrong IP/port | Start the server first; verify port 7777 is not blocked |
| `[CLIENT] Failed to initiate connection` | Server started after client, or wrong address | Start server first; check the IP in `Main.gd` |
| `[SERVER] Failed to create server` | Port 7777 already in use | Kill the other process using that port, or change `DEFAULT_PORT` |
| Black screen / no window (server) | Expected — `--headless` suppresses the display | Check terminal output instead |
| Two clients connect but only one controls characters | Intended — for solo testing, both clients share Team A control | No fix needed; multi-client auth is a future feature |
