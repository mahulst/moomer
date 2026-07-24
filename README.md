# moomer

A macOS screen-annotation tool written in [Odin](https://odin-lang.org/).

On launch it captures the main display and presents the screenshot as a
borderless, full-screen overlay. You can then zoom into pixels, spotlight the
cursor, and mirror the view — useful for inspecting UI, counting pixels, or
presenting.

## Demo

https://github.com/user-attachments/assets/moomer.mp4

<video src="moomer.mp4" controls width="100%"></video>

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

