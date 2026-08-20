# Quill — Virtual Keyboard for Omarchy

A beautiful, dependency-free on-screen virtual keyboard for **Omarchy** (Hyprland)
Quattro. Built with **QML** for the UI and **C++** for native key injection.

- No JavaScript, no Python, no network access.
- Keystrokes are injected through the Linux **uinput** kernel interface — no
  external tools (`ydotool`, `wtype`, …) and no root required.
- Ships both as a **bar widget** and as a standalone **floating app** (a native
  Omarchy `panel` you can summon from a keybinding).
- **Drag the handle** at the top of the keyboard to move it anywhere on screen.
- MIT licensed.

## How it works

```
BarWidget.qml  ──►  Panel.qml  ──►  Quickshell Process
 (bar icon)        (keyboard UI)      │ writes "d 30" / "u 30"
                                       ▼
                                 quill-inject (C++)
                                       │
                                       ▼
                                 /dev/uinput  ──► focused window
```

The QML keyboard sends Linux keycodes (e.g. `30` = `KEY_A`) to a long-running
`quill-inject` helper over its stdin. `quill-inject` translates them into
`uinput` events. Shift is sent as a real `KEY_LEFTSHIFT` modifier.

The keyboard surface is a fork of Omarchy's own `KeyboardPanel` (layer-shell
popup) so it docks above everything, never steals keyboard focus (so typed keys
reach the app you're actually using), and can be dragged anywhere.

## Files

```
quill/
├── manifest.json          # Omarchy plugin manifest (bar-widget + panel kinds)
├── BarWidget.qml          # Bar entry point (keyboard icon, toggles the panel)
├── Panel.qml              # Shared keyboard surface (used by both kinds)
├── QuillPanel.qml         # Draggable layer-shell surface (adapted from the shell)
├── QuillKey.qml           # Reusable key component (Style-free, theme-driven)
├── src/quill-inject.cpp   # C++ uinput key injector
├── Makefile               # Build the native helper (no cmake required)
├── CMakeLists.txt         # Build for packaging
├── build.sh               # Convenience cmake build/install script
├── udev/99-quill-uinput.rules
├── LICENSE                # MIT
└── README.md
```

## Prerequisites

- A C++17 compiler (`g++`/`clang++`). `cmake` is optional (a `Makefile` is
  provided so you can build with just `make`).
- Linux kernel headers providing `<linux/uinput.h>` (present on every standard
  kernel).
- Access to `/dev/uinput` (see udev rule below).

## 1. Build & install the native helper

With `make`:

```sh
cd quill
make            # builds ./quill-inject
cp quill-inject ~/.local/bin/   # ensure ~/.local/bin is on PATH
```

Or with the cmake script:

```sh
./build.sh      # installs to ~/.local/bin/quill-inject
```

Verify:

```sh
which quill-inject
```

### Grant /dev/uinput access

```sh
sudo cp udev/99-quill-uinput.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo usermod -aG input "$USER"
```

Then log out and back in (or `newgrp input`).

## 2. Install the plugin

From a git repo:

```sh
omarchy plugin add https://github.com/b7s/quill.git --enable
```

Or copy the folder manually (use the plugin id as the folder name):

```sh
cp -r quill ~/.config/omarchy/plugins/io.github.b7s.quill
omarchy plugin enable io.github.b7s.quill
```

Validate the manifest and QML:

```sh
PLUGIN_ID="io.github.b7s.quill"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
omarchy plugin validate "$PLUGIN_DIR"
```

Confirm it is discovered and enabled:

```sh
omarchy plugin list --json | jq --arg id "$PLUGIN_ID" '.[] | select(.id == $id)'
```

### Put it on the bar (optional)

The plugin is a floating `panel` app on its own; the bar widget is just a quick
toggle. To add the bar icon:

```sh
omarchy bar put io.github.b7s.quill --section right
```

## 3. Usage

- **From the bar:** click the keyboard icon (nf-md-keyboard) to show/hide it.
- **As a standalone app:** summon it directly — no bar required:

  ```sh
  omarchy-shell shell summon io.github.b7s.quill '{}'
  ```

  Bind that to a keybinding in your Hyprland config for a one-key virtual
  keyboard (e.g. `SUPER + K`):

  ```ini
  bind = SUPER, K, exec, omarchy-shell shell summon io.github.b7s.quill '{}'
  ```

- **Drag the top handle** (`⠿ drag`) to move the keyboard anywhere on screen.
- **Close** with the `✕` button (top-right). The surface intentionally does
  not grab keyboard focus, so `Escape` won't dismiss it — that's what keeps your
  keystrokes flowing to the app you're typing into.
- Click keys to type into the focused window. **Shift** toggles shifted
  characters; **⌫** backspace, **Enter**, **Tab**, **Space** are provided.

## Tuning the layout

Edit the `rows` property in `Panel.qml`. Each key is
`{ n:"normal label", s:"shifted label", c:<linux keycode>, type:"char"|"shift"|"back"|"enter"|"tab"|"space", w:<width factor> }`.
Linux keycodes follow `<linux/input.h>` (`KEY_A`=30, `KEY_1`=2, …).

## Uninstall

```sh
omarchy plugin remove io.github.b7s.quill
rm -rf ~/.config/omarchy/plugins/io.github.b7s.quill
```

## Security notes

- `quill-inject` reads only short lines from stdin and bounds-checks every
  keycode (`0 <= code < KEY_MAX`) before forwarding it to the kernel.
- It never opens a network socket and never elevates privileges.
- The keyboard only injects into the currently focused window, exactly like a
  physical keyboard.
