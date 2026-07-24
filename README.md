# moomer

A macOS screen-annotation tool written in [Odin](https://odin-lang.org/).

On launch it captures the main display and presents the screenshot as a
borderless, full-screen overlay. You can then zoom into pixels, spotlight the
cursor, and mirror the view — useful for inspecting UI, counting pixels, or
presenting.

## Demo
<video src="https://github.com/user-attachments/assets/4a9256ab-eaa0-4dbf-9f75-21b698579e11" controls width="100%"></video>

## Download

Grab the latest macOS build from the
[Releases](https://github.com/mahulst/moomer/releases/latest) page
(`moomer` binary or `moomer-<version>-macos.tar.gz`).

```sh
# make it executable and run
chmod +x moomer
xattr -d com.apple.quarantine moomer   # clear Gatekeeper quarantine if needed
./moomer
```

## Controls

| Input                 | Action                                                              |
| --------------------- | ------------------------------------------------------------------ |
| **Scroll**            | Zoom in / out at the mouse cursor (nearest-neighbour, crisp pixels) |
| **Ctrl + Scroll**     | Grow / shrink the spotlight radius                                  |
| **Hold Ctrl**         | Dim the screen except a circular spotlight that follows the cursor  |
| **Option**            | Toggle a horizontal mirror flip, anchored at the cursor            |
| **Esc**               | Dismiss the overlay and quit                                        |

## Build & run

```sh
odin build . -out:moomer && ./moomer
```

## Permissions

Screen capture requires **Screen Recording** permission for the launching
process (System Settings → Privacy & Security → Screen Recording).

