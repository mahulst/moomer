# moomer

A macOS screen-annotation tool written in [Odin](https://odin-lang.org/).

On launch it captures the main display and presents the screenshot as a
borderless, full-screen overlay. You can then zoom into pixels, spotlight the
cursor, and mirror the view — useful for inspecting UI, counting pixels, or
presenting.

## Demo
<video src="https://github.com/user-attachments/assets/4a9256ab-eaa0-4dbf-9f75-21b698579e11" controls width="100%"></video>

## Install

Download `Moomer-<version>-macos.dmg` from the
[Releases](https://github.com/mahulst/moomer/releases/latest) page, open it,
and drag **Moomer** into your **Applications** folder.

The app is signed with a Developer ID and notarized by Apple, so it launches
without any Gatekeeper warnings — no `xattr` workaround needed.

Moomer runs as a menu-bar app (no Dock icon). Click the cow icon in the menu
bar, or press the global hotkey **⌘⇧8**, to capture the screen. On first use
macOS will ask for **Screen Recording** permission — grant it, then trigger
the capture again.

## Controls

| Input                 | Action                                                              |
| --------------------- | ------------------------------------------------------------------ |
| **Scroll**            | Zoom in / out at the mouse cursor (0.2x–100x, nearest-neighbour, crisp pixels) |
| **Click & drag**      | Pan the zoomed image around                                        |
| **Ctrl + Scroll**     | Grow / shrink the spotlight radius                                  |
| **Hold Ctrl**         | Dim the screen except a circular spotlight that follows the cursor  |
| **Option**            | Toggle a horizontal mirror flip, anchored at the cursor            |
| **Hold Shift**        | Measure mouse movement in image pixels from where Shift was pressed (border-crossing count, Retina-aware) |
| **Shift + c**         | Copy the current Shift selection to the clipboard as a PNG image   |
| **Shift + a**         | Save the current Shift selection as a PNG to `~/.moomer/screenshots/` (UTC-timestamped) and copy its path to the clipboard |
| **c**                 | Copy the color of the pixel under the cursor as a hex string (e.g. `#3FA9F5`) |
| **m**                 | Toggle annotation mode — click for a 2px magenta dot, click-drag for a freehand 2px magenta line, pinned to the image |
| **g**                 | Toggle a thin light-grey grid on image-pixel edges (shown once zoomed in enough) |
| **0**                 | Reset zoom, pan, and flip to the original view                     |
| **Esc**               | Dismiss the overlay and quit                                        |

## Build & run

Build and run the bare capture tool directly:

```sh
odin build . -out:moomer && ./moomer
```

Or build the full menu-bar app bundle (launcher + capture tool):

```sh
./build_app.sh            # builds dist/Moomer.app (ad-hoc signed)
./build_app.sh install    # also copies it to /Applications
```

Releases are produced by CI, which signs the bundle with a Developer ID,
notarizes it, and packages it as a DMG.

## Permissions

Screen capture requires **Screen Recording** permission for the launching
process (System Settings → Privacy & Security → Screen Recording).

## Hotkey with skhd

The `.app` already binds a global **⌘⇧8** hotkey via its menu-bar launcher. If
you instead run the bare `moomer` binary, you can bind your own shortcut with
[skhd](https://github.com/koekeishiya/skhd) by adding this to
`~/.config/skhd/skhdrc`:

```
# Launch moomer screen annotation (Cmd + Option + S)
cmd + alt - s : ~/.local/bin/moomer
```

Then reload skhd:

```sh
skhd --reload
```

Grant **Screen Recording** permission to skhd (the launching process) so the
capture works.


