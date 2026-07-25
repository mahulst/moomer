# moomer

A macOS screen-annotation tool written in [Odin](https://odin-lang.org/).

## What it does

On launch it captures the main display and presents the screenshot as a
borderless, full-screen overlay window that covers the screen exactly (no
border, no animation). While the overlay is up:

- **Hold Ctrl** — darkens the whole screen except a circular "spotlight" that
  follows the mouse cursor. **Ctrl + scroll** resizes the spotlight radius.
- **Scroll** — zooms in/out at the cursor. Zoom ranges from 0.2x (smaller than
  original, shown centered on the dimmed background) up to 100x.
- **Click & drag** — pans the zoomed image around.
- **Option** — toggles a horizontal mirror flip about the cursor.
- **Hold Shift** — shows a label below-right of the cursor measuring how far the
  mouse has moved, in real image pixels, since Shift was pressed. It counts
  pixel-border crossings (press anywhere inside a pixel, then each pixel the
  cursor moves adds 1) and is Retina-aware, so the count is in true captured
  image pixels regardless of zoom level.
- **Press 0** — resets zoom, pan, and flip to the original view.
- **Press Esc** — dismisses the overlay and quits.

## Build & run

```sh
odin build . -out:moomer && ./moomer
```

## Architecture

Single-file program (`screenshot.odin`). It talks directly to macOS system
frameworks via Odin's foreign imports and first-class Objective-C support
(`intrinsics.objc_send`, `@(objc_class=...)`), with no third-party
dependencies.

- **Capture** — `CGDisplayCreateImage` (CoreGraphics) grabs the display.
- **Presentation** — a borderless `NSWindow` at `NSScreenSaverWindowLevel`
  holds a container `NSView` with an `NSImageView` (the screenshot) and a
  layer-hosting overlay `NSView` on top.
- **Spotlight** — a `CAShapeLayer` fills the overlay with 75% black using an
  even-odd path (full rect + circle) that punches a transparent hole around
  the cursor. `CATransaction` with disabled actions keeps updates instant.
- **Input** — an `NSTimer` polls at 60fps and reads global key/mouse state via
  `CGEventSourceKeyState` and `NSEvent.mouseLocation`. Polling is used instead
  of event monitors because the borderless window cannot become key, and it
  needs no Accessibility permission.

## Notes

- Screen capture requires **Screen Recording** permission for the launching
  terminal (System Settings → Privacy & Security → Screen Recording).
- Layer coordinates use AppKit's bottom-left origin, matching
  `NSEvent.mouseLocation`, so no coordinate flipping is needed.
- The dimming overlay must live in its own layer-hosting `NSView`;
  `NSImageView` manages its own backing layer and won't reliably render an
  added sublayer.
- When running the user can press Escape, which will close it. Don't take it as an unexpected crash
