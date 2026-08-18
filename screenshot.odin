package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:time"
import "base:intrinsics"
import "base:runtime"
import NS "core:sys/darwin/Foundation"

foreign import CoreGraphics "system:CoreGraphics.framework"
foreign import AppKit "system:AppKit.framework"
foreign import QuartzCore "system:QuartzCore.framework"

// --- CoreGraphics ---
CGDirectDisplayID :: u32
CGImageRef :: rawptr
CGRect :: NS.Rect
CGSize :: NS.Size
CGPoint :: NS.Point
CGFloat :: NS.Float
CGColorRef :: rawptr
CGMutablePathRef :: rawptr
CGPathRef :: rawptr
CGColorSpaceRef :: rawptr

CGAffineTransform :: struct {
	a, b, c, d, tx, ty: CGFloat,
}

foreign CoreGraphics {
	CGMainDisplayID :: proc "c" () -> CGDirectDisplayID ---
	CGPreflightScreenCaptureAccess :: proc "c" () -> bool ---
	CGRequestScreenCaptureAccess :: proc "c" () -> bool ---
	CGDisplayCreateImage :: proc "c" (display: CGDirectDisplayID) -> CGImageRef ---
	CGDisplayBounds :: proc "c" (display: CGDirectDisplayID) -> CGRect ---
	CGImageRelease :: proc "c" (image: CGImageRef) ---
	CGImageGetWidth :: proc "c" (image: CGImageRef) -> uint ---
	CGImageGetHeight :: proc "c" (image: CGImageRef) -> uint ---
	CGImageCreateWithImageInRect :: proc "c" (image: CGImageRef, rect: CGRect) -> CGImageRef ---

	CGPathCreateMutable :: proc "c" () -> CGMutablePathRef ---
	CGPathAddRect :: proc "c" (path: CGMutablePathRef, m: rawptr, rect: CGRect) ---
	CGPathAddEllipseInRect :: proc "c" (path: CGMutablePathRef, m: rawptr, rect: CGRect) ---
	CGPathMoveToPoint :: proc "c" (path: CGMutablePathRef, m: rawptr, x, y: CGFloat) ---
	CGPathAddLineToPoint :: proc "c" (path: CGMutablePathRef, m: rawptr, x, y: CGFloat) ---
	CGPathRelease :: proc "c" (path: CGPathRef) ---

	CGColorCreateGenericRGB :: proc "c" (r, g, b, a: CGFloat) -> CGColorRef ---
	CGColorRelease :: proc "c" (color: CGColorRef) ---

	// Reading a single pixel: draw a 1x1 crop into an RGBA bitmap context.
	CGColorSpaceCreateDeviceRGB :: proc "c" () -> CGColorSpaceRef ---
	CGColorSpaceRelease :: proc "c" (space: CGColorSpaceRef) ---
	CGBitmapContextCreate :: proc "c" (data: rawptr, width, height, bitsPerComponent, bytesPerRow: uint, space: CGColorSpaceRef, bitmapInfo: u32) -> rawptr ---
	CGContextDrawImage :: proc "c" (ctx: rawptr, rect: CGRect, image: CGImageRef) ---
	CGContextRelease :: proc "c" (ctx: rawptr) ---

	// Reads global key state without special permission.
	// stateID: kCGEventSourceStateCombinedSessionState = 0
	CGEventSourceKeyState :: proc "c" (stateID: i32, key: u16) -> NS.BOOL ---
	CGEventSourceButtonState :: proc "c" (stateID: i32, button: u32) -> NS.BOOL ---
}

// --- AppKit types via Odin objc intrinsics ---
@(objc_class = "NSApplication")
NSApplication :: struct {
	using _: NS.Object,
}

@(objc_class = "NSWindow")
NSWindow :: struct {
	using _: NS.Object,
}

@(objc_class = "NSImage")
NSImage :: struct {
	using _: NS.Object,
}

@(objc_class = "NSImageView")
NSImageView :: struct {
	using _: NS.Object,
}

@(objc_class = "NSPasteboard")
NSPasteboard :: struct {
	using _: NS.Object,
}

@(objc_class = "NSBitmapImageRep")
NSBitmapImageRep :: struct {
	using _: NS.Object,
}

@(objc_class = "NSView")
NSView :: struct {
	using _: NS.Object,
}

@(objc_class = "NSEvent")
NSEvent :: struct {
	using _: NS.Object,
}

@(objc_class = "CAShapeLayer")
CAShapeLayer :: struct {
	using _: NS.Object,
}

@(objc_class = "CATextLayer")
CATextLayer :: struct {
	using _: NS.Object,
}

@(objc_class = "CALayer")
CALayer :: struct {
	using _: NS.Object,
}

@(objc_class = "CATransaction")
CATransaction :: struct {
	using _: NS.Object,
}

@(objc_class = "NSTimer")
NSTimer :: struct {
	using _: NS.Object,
}

@(objc_class = "NSRunLoop")
NSRunLoop :: struct {
	using _: NS.Object,
}

msgSend :: intrinsics.objc_send

NSApplicationActivationPolicyRegular :: NS.Integer(0)
NSWindowStyleMaskBorderless :: NS.UInteger(0)
NSBackingStoreBuffered :: NS.UInteger(2)
NSScreenSaverWindowLevel :: NS.Integer(1000)
NSImageScaleAxesIndependently :: NS.Integer(3)

NSEventMaskKeyDown :: NS.UInteger(1) << 10
NSEventMaskLeftMouseDown :: NS.UInteger(1) << 1
NSEventMaskMouseMoved :: NS.UInteger(1) << 5
NSEventMaskFlagsChanged :: NS.UInteger(1) << 12
NSEventMaskScrollWheel :: NS.UInteger(1) << 22

// NSEventModifierFlagControl
NSEventModifierFlagControl :: NS.UInteger(1) << 18

// Virtual key codes for the Control keys.
kVK_Control :: u16(0x3B)
kVK_RightControl :: u16(0x3E)
kVK_Escape :: u16(0x35)
kVK_ANSI_0 :: u16(0x1D)
kVK_Option :: u16(0x3A)
kVK_RightOption :: u16(0x3D)
kVK_Shift :: u16(0x38)
kVK_RightShift :: u16(0x3C)
kVK_ANSI_C :: u16(0x08)
kVK_ANSI_A :: u16(0x00)
kVK_ANSI_G :: u16(0x05)
kVK_ANSI_M :: u16(0x2E)
kCGEventSourceStateCombined :: i32(0)
kCGMouseButtonLeft :: u32(0)

g_spotlight_radius: CGFloat = 100
MIN_RADIUS :: CGFloat(20)
MAX_RADIUS :: CGFloat(600)

// Globals used by the event handlers.
g_overlay: ^CAShapeLayer // the dimming layer
g_spot_ring: ^CAShapeLayer // faint outline around the spotlight circle
g_bounds: CGRect
g_ctrl_down: bool

// Zoom state. The content layer is transformed by (scale, offset) mapping
// content coords -> screen coords: screen = scale*content + offset.
g_content_layer: ^CALayer
g_scale: CGFloat = 1
g_offset: CGPoint = {0, 0}
g_flipped: bool // horizontal mirror, toggled by Option
g_opt_down: bool
g_opt_armed: bool // ignore Option until it has been released once (it's held at launch)

// Click-and-drag pan state.
g_pan_down: bool
g_pan_last: CGPoint

g_zero_down: bool // edge guard for the "0" reset key

// Coordinate readout shown while Shift is held.
g_img_height: CGFloat // captured image height in pixels, for top-left origin
g_backing_scale: CGFloat = 1 // image pixels per point (2 on Retina)

// Measurement anchor: image pixel under the cursor when Shift was pressed.
g_measure_active: bool
g_measure_anchor: CGPoint
g_coord_layer: ^CALayer     // dark background box
g_coord_text: ^CATextLayer  // the readout text inside the box
g_rect_layer: ^CAShapeLayer // outline of the dragged area while Shift held
g_grid_layer: ^CAShapeLayer // pixel-edge grid, toggled by "g"
g_grid_on: bool             // whether the grid is currently enabled
g_grid_down: bool           // edge guard for the "g" toggle key

// Full-resolution captured image, kept so a Shift selection can be cropped and
// copied to the clipboard. Selection bounds are in image-pixel space with a
// top-left origin (px_lo/py_lo inclusive, px_hi/py_hi exclusive edges).
g_image: CGImageRef
g_sel_px_lo, g_sel_px_hi, g_sel_py_lo, g_sel_py_hi: f64
g_copy_down: bool
g_save_down: bool // edge guard for the save-to-file "a" (with Shift)
g_pick_down: bool // edge guard for the color-pick "c" (no Shift)

// Annotation ("m") mode. Strokes are stored in content-point space (bottom-left
// origin, matching the un-zoomed content layer) so they stay pinned to the
// image when zooming/panning. Each frame the path is rebuilt in screen space.
g_annotate_on: bool     // whether annotation mode is active
g_annotate_down: bool   // edge guard for the "m" toggle key
g_anno_layer: ^CAShapeLayer
g_strokes: [dynamic][dynamic]CGPoint // each stroke is a list of content-space points
g_anno_drawing: bool    // a stroke is currently being drawn (mouse held)

MIN_SCALE :: CGFloat(0.2)
MAX_SCALE :: CGFloat(100)

apply_zoom :: proc "c" () {
	msgSend(nil, CATransaction, "begin")
	msgSend(nil, CATransaction, "setDisableActions:", NS.BOOL(true))
	a := g_flipped ? -g_scale : g_scale
	t := CGAffineTransform{a, 0, 0, g_scale, g_offset.x, g_offset.y}
	msgSend(nil, g_content_layer, "setAffineTransform:", t)
	msgSend(nil, CATransaction, "commit")
}

// Toggle horizontal mirror about screen point `m`, keeping the pixel under the
// cursor fixed. Mapping is screen.x = a*content.x + offset.x with a = +/-scale.
toggle_flip :: proc "c" (m: CGPoint) {
	a := g_flipped ? -g_scale : g_scale
	// content under the cursor before flipping
	c := (m.x - g_offset.x) / a
	g_flipped = !g_flipped
	new_a := g_flipped ? -g_scale : g_scale
	// keep m fixed: m = new_a*c + offset.x
	g_offset.x = m.x - new_a * c
	clamp_offset()
	apply_zoom()
}

clamp_offset :: proc "c" () {
	w := g_bounds.size.width
	h := g_bounds.size.height
	a := g_flipped ? -g_scale : g_scale

	// When zoomed out below original size the content is smaller than the
	// screen, so center it instead of forcing it to cover the whole screen.
	if g_scale < 1 {
		// x: center the |a|*w-wide content in w.
		center_lo := (w - g_scale * w) / 2
		g_offset.x = g_flipped ? center_lo + g_scale * w : center_lo
		// y: center the g_scale*h-tall content in h.
		g_offset.y = (h - g_scale * h) / 2
		return
	}

	// x extent depends on flip sign; compute screen-space min/max of content.
	x0 := g_offset.x        // screen x of content x=0
	x1 := a * w + g_offset.x // screen x of content x=w
	lo := min(x0, x1)
	hi := max(x0, x1)
	// keep content covering [0, w]: lo <= 0 and hi >= w
	if lo > 0 {g_offset.x -= lo}
	if hi < w {g_offset.x += w - hi}
	min_y := h - g_scale * h
	g_offset.y = clamp(g_offset.y, min_y, 0)
}

// Zoom by factor f keeping screen point `m` fixed.
zoom_at :: proc "c" (m: CGPoint, f: CGFloat) {
	new_scale := clamp(g_scale * f, MIN_SCALE, MAX_SCALE)
	ff := new_scale / g_scale
	g_scale = new_scale
	// Same anchor formula works for both x and y; the x sign is carried by
	// g_flipped and re-applied in apply_zoom/clamp_offset.
	g_offset.x = m.x - ff * (m.x - g_offset.x)
	g_offset.y = m.y - ff * (m.y - g_offset.y)
	clamp_offset()
	apply_zoom()
}

// Reset zoom, pan, and flip to the original view.
reset_view :: proc "c" () {
	g_scale = 1
	g_flipped = false
	g_offset = {0, 0}
	clamp_offset()
	apply_zoom()
}

// Pan the content by a screen-space delta, keeping it clamped on-screen.
pan_by :: proc "c" (dx, dy: CGFloat) {	g_offset.x += dx
	g_offset.y += dy
	clamp_offset()
	apply_zoom()
}

scroll_handler :: proc "c" (user_data: rawptr, event: ^NSEvent) -> ^NSEvent {
	dy := msgSend(CGFloat, event, "scrollingDeltaY")
	loc := msgSend(CGPoint, NSEvent, "mouseLocation")

	ctrl :=
		bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_Control)) ||
		bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_RightControl))

	if ctrl {
		// Control+scroll adjusts the spotlight radius instead of zooming.
		g_spotlight_radius = clamp(g_spotlight_radius + dy, MIN_RADIUS, MAX_RADIUS)
		update_spotlight(loc, true)
		return event
	}

	// Positive dy = scroll up = zoom in.
	f := CGFloat(1) + dy * 0.01
	if f < 0.1 {f = 0.1}
	zoom_at(loc, f)
	return event
}

// Handles keyDown events so fast single key taps (e.g. Escape) are never
// missed the way polling can. A local monitor is enough since our overlay
// window receives key events while the app is active.
key_handler :: proc "c" (user_data: rawptr, event: ^NSEvent) -> ^NSEvent {
	code := msgSend(u16, event, "keyCode")
	context = runtime.default_context()
	fmt.printfln("[key] keyDown keycode 0x%X (%d)", code, code)
	if code == kVK_Escape {
		fmt.println("[esc] Escape keyDown - terminating")
		app := msgSend(^NSApplication, NSApplication, "sharedApplication")
		msgSend(nil, app, "terminate:", rawptr(nil))
		return nil
	}
	return event
}

// --- Minimal global block wrapping scroll_handler ---
// The stock NS.Block_createGlobalWithParam invoke returns void, but a local
// event monitor's handler must return NSEvent*. We build a global block whose
// invoke returns the event.
Block_Literal :: struct {
	isa:        rawptr,
	flags:      u32,
	reserved:   u32,
	invoke:     rawptr,
	descriptor: rawptr,
	user_proc:  rawptr,
	user_data:  rawptr,
}

Block_Descriptor :: struct {
	reserved: uint,
	size:     uint,
}

foreign import libSystem "system:System.framework"
foreign libSystem {
	_NSConcreteGlobalBlock: intrinsics.objc_class
}

scroll_block_descriptor := Block_Descriptor {
	reserved = 0,
	size     = size_of(Block_Literal),
}

scroll_block_invoke :: proc "c" (bl: ^Block_Literal, event: ^NSEvent) -> ^NSEvent {
	fn := (proc "c" (rawptr, ^NSEvent) -> ^NSEvent)(bl.user_proc)
	return fn(bl.user_data, event)
}

scroll_block: Block_Literal

key_block_invoke :: proc "c" (bl: ^Block_Literal, event: ^NSEvent) -> ^NSEvent {
	fn := (proc "c" (rawptr, ^NSEvent) -> ^NSEvent)(bl.user_proc)
	return fn(bl.user_data, event)
}

key_block: Block_Literal

update_spotlight :: proc "c" (mouse: CGPoint, visible: bool) {
	// Disable implicit animations for instant, no-animation updates.
	msgSend(nil, CATransaction, "begin")
	msgSend(nil, CATransaction, "setDisableActions:", NS.BOOL(true))

	if !visible {
		msgSend(nil, g_overlay, "setHidden:", NS.BOOL(true))
		msgSend(nil, g_spot_ring, "setHidden:", NS.BOOL(true))
		msgSend(nil, CATransaction, "commit")
		return
	}

	// The overlay is not zoomed, so draw directly in screen coordinates and
	// keep a constant on-screen radius regardless of zoom level.
	// Even-odd path: full rect + circle hole => circle stays clear, rest dimmed.
	path := CGPathCreateMutable()
	CGPathAddRect(path, nil, g_bounds)
	circle := CGRect {
		{mouse.x - g_spotlight_radius, mouse.y - g_spotlight_radius},
		{g_spotlight_radius * 2, g_spotlight_radius * 2},
	}
	CGPathAddEllipseInRect(path, nil, circle)

	msgSend(nil, g_overlay, "setPath:", path)
	msgSend(nil, g_overlay, "setHidden:", NS.BOOL(false))

	// Outline just the spotlight circle.
	ring_path := CGPathCreateMutable()
	CGPathAddEllipseInRect(ring_path, nil, circle)
	msgSend(nil, g_spot_ring, "setPath:", ring_path)
	msgSend(nil, g_spot_ring, "setHidden:", NS.BOOL(false))
	CGPathRelease(ring_path)
	CGPathRelease(path)

	msgSend(nil, CATransaction, "commit")
}

// Show the mouse movement in image pixels since Shift was pressed.
update_coords :: proc "c" (mouse: CGPoint, visible: bool) {
	msgSend(nil, CATransaction, "begin")
	msgSend(nil, CATransaction, "setDisableActions:", NS.BOOL(true))

	if !visible {
		g_measure_active = false
		msgSend(nil, g_coord_layer, "setHidden:", NS.BOOL(true))
		msgSend(nil, g_rect_layer, "setHidden:", NS.BOOL(true))
		msgSend(nil, CATransaction, "commit")
		return
	}

	// screen = a*content + offset  =>  content = (screen - offset) / a
	// Content coords are in points; multiply by the backing scale to get real
	// image pixels (Retina displays capture at 2x the point dimensions).
	a := g_flipped ? -g_scale : g_scale
	cx := (mouse.x - g_offset.x) / a * g_backing_scale
	// Content y is bottom-left origin; convert to top-left pixel space.
	cy := (g_bounds.size.height - (mouse.y - g_offset.y) / g_scale) * g_backing_scale

	// On the Shift press edge, anchor the measurement at the current pixel.
	if !g_measure_active {
		g_measure_anchor = {cx, cy}
		g_measure_active = true
	}

	// Inclusive pixel span, matching the drawn selection box: both the start
	// and current pixel are counted, so a stationary cursor reads 1.
	dx := int(abs(math.floor(f64(cx)) - math.floor(f64(g_measure_anchor.x)))) + 1
	dy := int(abs(math.floor(f64(cy)) - math.floor(f64(g_measure_anchor.y)))) + 1

	context = runtime.default_context()
	str := fmt.ctprintf("x: %dpx\ny: %dpx", dx, dy)
	ns_str := msgSend(^NS.String, NS.String, "stringWithUTF8String:", str)
	msgSend(nil, g_coord_text, "setString:", ns_str)

	// Size the box snugly around the text, with a bit of padding.
	PAD :: CGFloat(6)
	FONT :: CGFloat(16)
	line_h := FONT * 1.25
	// Longest line's character count drives the width (monospace estimate).
	nx := len(fmt.tprintf("x: %dpx", dx))
	ny := len(fmt.tprintf("y: %dpx", dy))
	cols := CGFloat(max(nx, ny))
	text_w := cols * FONT * 0.6
	text_h := line_h * 2
	box_w := text_w + PAD * 2
	box_h := text_h + PAD * 2

	// Position the box below-right of the cursor.
	fr := CGRect{{mouse.x + 16, mouse.y - box_h - 8}, {box_w, box_h}}
	msgSend(nil, g_coord_layer, "setFrame:", fr)
	// Text sits inset by the padding within the box.
	msgSend(nil, g_coord_text, "setFrame:", CGRect{{PAD, PAD}, {text_w, text_h}})
	msgSend(nil, g_coord_layer, "setHidden:", NS.BOOL(false))

	// Draw a rectangle snapped to whole image-pixel edges. The selection spans
	// from the start pixel through the current pixel, both fully included.
	a0 := g_measure_anchor
	// Pixel index range (inclusive) on each axis.
	px_lo := math.floor(f64(min(a0.x, cx)))
	px_hi := math.floor(f64(max(a0.x, cx))) + 1 // +1 to include the far pixel's right edge
	py_lo := math.floor(f64(min(a0.y, cy)))
	py_hi := math.floor(f64(max(a0.y, cy))) + 1

	// Remember the current selection so a right-Shift release can crop+copy it.
	g_sel_px_lo = px_lo
	g_sel_px_hi = px_hi
	g_sel_py_lo = py_lo
	g_sel_py_hi = py_hi

	// Map image-pixel coords back to screen space.
	// screen.x = offset.x + a * px / backing ; screen.y = offset.y + (H - py/backing) * scale
	sx :: proc "c" (px: f64) -> CGFloat {
		a := g_flipped ? -g_scale : g_scale
		return g_offset.x + a * CGFloat(px) / g_backing_scale
	}
	sy :: proc "c" (py: f64) -> CGFloat {
		return g_offset.y + (g_bounds.size.height - CGFloat(py) / g_backing_scale) * g_scale
	}
	x0 := sx(px_lo)
	x1 := sx(px_hi)
	y0 := sy(py_lo)
	y1 := sy(py_hi)
	rx := min(x0, x1)
	ry := min(y0, y1)
	rw := abs(x1 - x0)
	rh := abs(y1 - y0)
	rect_path := CGPathCreateMutable()
	CGPathAddRect(rect_path, nil, CGRect{{rx, ry}, {rw, rh}})
	msgSend(nil, g_rect_layer, "setPath:", rect_path)
	msgSend(nil, g_rect_layer, "setHidden:", NS.BOOL(false))
	CGPathRelease(rect_path)

	msgSend(nil, CATransaction, "commit")
}

// Draw thin grid lines on image-pixel edges, but only when zoom makes each
// pixel large enough on screen to be worth outlining. Lines are computed in
// screen space and clipped to the visible bounds; toggled by "g".
update_grid :: proc "c" () {
	msgSend(nil, CATransaction, "begin")
	msgSend(nil, CATransaction, "setDisableActions:", NS.BOOL(true))

	// Points on screen occupied by one image pixel: |a|*(1/backing).
	step := f64(g_scale / g_backing_scale)
	// Below this, lines would crowd together into a solid grey wash.
	MIN_PIXEL_POINTS :: 8.0
	if !g_grid_on || step < MIN_PIXEL_POINTS {
		msgSend(nil, g_grid_layer, "setHidden:", NS.BOOL(true))
		msgSend(nil, CATransaction, "commit")
		return
	}

	w := f64(g_bounds.size.width)
	h := f64(g_bounds.size.height)
	ax := f64(g_flipped ? -g_scale : g_scale)
	off_x := f64(g_offset.x)
	off_y := f64(g_offset.y)
	iw := f64(CGImageGetWidth(g_image))
	ih := f64(CGImageGetHeight(g_image))
	backing := f64(g_backing_scale)

	// screen.x = off_x + ax*px/backing ; screen.y = off_y + (H - py/backing)*scale
	sx :: proc "c" (px, ax, off_x, backing: f64) -> f64 {
		return off_x + ax * px / backing
	}

	path := CGPathCreateMutable()

	// Vertical lines at every image-pixel column edge visible on screen.
	for px := 0.0; px <= iw; px += 1 {
		x := sx(px, ax, off_x, backing)
		if x < 0 || x > w {
			continue
		}
		CGPathAddRect(path, nil, CGRect{{CGFloat(x), 0}, {0, CGFloat(h)}})
	}
	// Horizontal lines at every image-pixel row edge visible on screen.
	for py := 0.0; py <= ih; py += 1 {
		y := off_y + (h - py / backing) * f64(g_scale)
		if y < 0 || y > h {
			continue
		}
		CGPathAddRect(path, nil, CGRect{{0, CGFloat(y)}, {CGFloat(w), 0}})
	}

	msgSend(nil, g_grid_layer, "setPath:", path)
	msgSend(nil, g_grid_layer, "setHidden:", NS.BOOL(false))
	CGPathRelease(path)

	msgSend(nil, CATransaction, "commit")
}

// Convert a screen point to content-point space (bottom-left origin), the
// coordinate space in which annotation strokes are stored so they stay pinned
// to the image across zoom/pan. Inverse of the apply_zoom transform.
screen_to_content :: proc "c" (m: CGPoint) -> CGPoint {
	a := g_flipped ? -g_scale : g_scale
	return {(m.x - g_offset.x) / a, (m.y - g_offset.y) / g_scale}
}

// Map a stored content-space point back to screen space (matches apply_zoom).
content_to_screen :: proc "c" (c: CGPoint) -> CGPoint {
	a := g_flipped ? -g_scale : g_scale
	return {a * c.x + g_offset.x, g_scale * c.y + g_offset.y}
}

// Rebuild the magenta annotation path in screen space each frame so it tracks
// zoom/pan while keeping a constant 2px on-screen line width.
update_annotation :: proc "c" () {
	msgSend(nil, CATransaction, "begin")
	msgSend(nil, CATransaction, "setDisableActions:", NS.BOOL(true))

	path := CGPathCreateMutable()
	for &stroke in g_strokes {
		n := len(stroke)
		if n == 0 {
			continue
		}
		if n == 1 {
			// A single click is a dot: a zero-length stroked subpath renders as
			// a round cap (a small filled dot) thanks to the round line cap.
			p := content_to_screen(stroke[0])
			CGPathMoveToPoint(path, nil, p.x, p.y)
			CGPathAddLineToPoint(path, nil, p.x, p.y)
			continue
		}
		p0 := content_to_screen(stroke[0])
		CGPathMoveToPoint(path, nil, p0.x, p0.y)
		for i in 1 ..< n {
			p := content_to_screen(stroke[i])
			CGPathAddLineToPoint(path, nil, p.x, p.y)
		}
	}

	msgSend(nil, g_anno_layer, "setPath:", path)
	msgSend(nil, g_anno_layer, "setHidden:", NS.BOOL(len(g_strokes) == 0))
	CGPathRelease(path)

	msgSend(nil, CATransaction, "commit")
}

// Crop the current Shift selection out of the captured image and place it on
// the general pasteboard as a bitmap-backed NSImage.
copy_selection :: proc "c" () {
	if g_image == nil {
		return
	}
	w := f64(CGImageGetWidth(g_image))
	h := f64(CGImageGetHeight(g_image))

	// Clamp to image bounds. CGImage rect origin is top-left, matching the
	// selection's stored top-left pixel space.
	x0 := math.clamp(g_sel_px_lo, 0, w)
	x1 := math.clamp(g_sel_px_hi, 0, w)
	y0 := math.clamp(g_sel_py_lo, 0, h)
	y1 := math.clamp(g_sel_py_hi, 0, h)
	rw := x1 - x0
	rh := y1 - y0
	if rw < 1 || rh < 1 {
		return
	}

	rect := CGRect{{CGFloat(x0), CGFloat(y0)}, {CGFloat(rw), CGFloat(rh)}}
	cropped := CGImageCreateWithImageInRect(g_image, rect)
	if cropped == nil {
		return
	}
	defer CGImageRelease(cropped)

	rep := msgSend(^NSBitmapImageRep, NSBitmapImageRep, "alloc")
	rep = msgSend(^NSBitmapImageRep, rep, "initWithCGImage:", cropped)
	if rep == nil {
		return
	}

	// Encode the bitmap as PNG data. NSBitmapImageFileTypePNG = 4.
	NSBitmapImageFileTypePNG :: NS.UInteger(4)
	empty := msgSend(^NS.Dictionary, NS.Dictionary, "dictionary")
	png := msgSend(
		^NS.Data,
		rep,
		"representationUsingType:properties:",
		NSBitmapImageFileTypePNG,
		empty,
	)
	if png == nil {
		return
	}

	// Write the PNG bytes to the general pasteboard under the PNG UTI.
	pb := msgSend(^NSPasteboard, NSPasteboard, "generalPasteboard")
	msgSend(nil, pb, "clearContents")
	png_type := msgSend(^NS.String, NS.String, "stringWithUTF8String:", cstring("public.png"))
	msgSend(NS.BOOL, pb, "setData:forType:", png, png_type)

	context = runtime.default_context()
	fmt.printfln("[shift] copied %.0fx%.0f px selection to clipboard", rw, rh)
}

// Crop the current Shift selection and save it as a PNG under
// ~/.moomer/screenshots/<UTC ISO8601 with ms>.png. The resulting file path is
// also placed on the general pasteboard as a plain string.
save_selection :: proc "c" () {
	context = runtime.default_context()

	if g_image == nil {
		return
	}
	w := f64(CGImageGetWidth(g_image))
	h := f64(CGImageGetHeight(g_image))

	x0 := math.clamp(g_sel_px_lo, 0, w)
	x1 := math.clamp(g_sel_px_hi, 0, w)
	y0 := math.clamp(g_sel_py_lo, 0, h)
	y1 := math.clamp(g_sel_py_hi, 0, h)
	rw := x1 - x0
	rh := y1 - y0
	if rw < 1 || rh < 1 {
		return
	}

	rect := CGRect{{CGFloat(x0), CGFloat(y0)}, {CGFloat(rw), CGFloat(rh)}}
	cropped := CGImageCreateWithImageInRect(g_image, rect)
	if cropped == nil {
		return
	}
	defer CGImageRelease(cropped)

	rep := msgSend(^NSBitmapImageRep, NSBitmapImageRep, "alloc")
	rep = msgSend(^NSBitmapImageRep, rep, "initWithCGImage:", cropped)
	if rep == nil {
		return
	}

	NSBitmapImageFileTypePNG :: NS.UInteger(4)
	empty := msgSend(^NS.Dictionary, NS.Dictionary, "dictionary")
	png := msgSend(
		^NS.Data,
		rep,
		"representationUsingType:properties:",
		NSBitmapImageFileTypePNG,
		empty,
	)
	if png == nil {
		return
	}

	// Build the destination directory ~/.moomer/screenshots and ensure it exists.
	home := os.get_env("HOME")
	if home == "" {
		fmt.eprintln("[shift] HOME not set, cannot save selection")
		return
	}
	dir := fmt.tprintf("%s/.moomer/screenshots", home)
	if !os.exists(dir) {
		if err := os.make_directory(fmt.tprintf("%s/.moomer", home)); err != nil && !os.exists(fmt.tprintf("%s/.moomer", home)) {
			fmt.eprintfln("[shift] mkdir failed: %v", err)
			return
		}
		if err := os.make_directory(dir); err != nil && !os.exists(dir) {
			fmt.eprintfln("[shift] mkdir failed: %v", err)
			return
		}
	}

	// Timestamped filename in UTC: YYYY-MM-DDTHH:MM:SS.mmmZ.png
	now := time.now()
	yy, mo, dd := time.date(now)
	hh, mi, ss := time.clock(now)
	ms := i64(now._nsec / 1_000_000 % 1000)
	name := fmt.tprintf(
		"%04d-%02d-%02dT%02d:%02d:%02d.%03dZ.png",
		yy, mo, dd, hh, mi, ss, ms,
	)
	path := fmt.tprintf("%s/%s", dir, name)

	bytes := msgSend(rawptr, png, "bytes")
	length := int(msgSend(NS.UInteger, png, "length"))
	if !os.write_entire_file(path, (cast([^]byte)bytes)[:length]) {
		fmt.eprintfln("[shift] failed to write %s", path)
		return
	}

	// Put the saved file path on the pasteboard as a string.
	pb := msgSend(^NSPasteboard, NSPasteboard, "generalPasteboard")
	msgSend(nil, pb, "clearContents")
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	path_str := msgSend(^NS.String, NS.String, "stringWithUTF8String:", cpath)
	str_type := msgSend(^NS.String, NS.String, "stringWithUTF8String:", cstring("public.utf8-plain-text"))
	msgSend(NS.BOOL, pb, "setString:forType:", path_str, str_type)

	fmt.printfln("[shift] saved %.0fx%.0f px selection to %s", rw, rh, path)
}

// Read the color of the image pixel under the cursor and copy its hex string
// (e.g. "#3FA9F5") to the general pasteboard.
copy_pixel_color :: proc "c" (mouse: CGPoint) {
	if g_image == nil {
		return
	}
	w := f64(CGImageGetWidth(g_image))
	h := f64(CGImageGetHeight(g_image))

	// Map screen point to top-left-origin image-pixel coords (mirrors update_coords).
	a := g_flipped ? -g_scale : g_scale
	cx := f64((mouse.x - g_offset.x) / a * g_backing_scale)
	cy := f64((g_bounds.size.height - (mouse.y - g_offset.y) / g_scale) * g_backing_scale)
	px := math.floor(cx)
	py := math.floor(cy)
	if px < 0 || py < 0 || px >= w || py >= h {
		return
	}

	// Crop out the 1x1 pixel and draw it into an RGBA8 bitmap to read its bytes.
	cropped := CGImageCreateWithImageInRect(g_image, CGRect{{CGFloat(px), CGFloat(py)}, {1, 1}})
	if cropped == nil {
		return
	}
	defer CGImageRelease(cropped)

	pixel: [4]u8
	space := CGColorSpaceCreateDeviceRGB()
	defer CGColorSpaceRelease(space)
	// kCGImageAlphaPremultipliedLast = 1
	ctx := CGBitmapContextCreate(&pixel, 1, 1, 8, 4, space, 1)
	if ctx == nil {
		return
	}
	CGContextDrawImage(ctx, CGRect{{0, 0}, {1, 1}}, cropped)
	CGContextRelease(ctx)

	context = runtime.default_context()
	hex := fmt.ctprintf("#%02X%02X%02X", pixel[0], pixel[1], pixel[2])

	pb := msgSend(^NSPasteboard, NSPasteboard, "generalPasteboard")
	msgSend(nil, pb, "clearContents")
	ns_str := msgSend(^NS.String, NS.String, "stringWithUTF8String:", hex)
	str_type := msgSend(^NS.String, NS.String, "stringWithUTF8String:", cstring("public.utf8-plain-text"))
	msgSend(NS.BOOL, pb, "setString:forType:", ns_str, str_type)

	fmt.printfln("[pick] copied color %s to clipboard", hex)
}

dismiss_handler :: proc "c" (user_data: rawptr, event: rawptr) {
	app := msgSend(^NSApplication, NSApplication, "sharedApplication")
	msgSend(nil, app, "terminate:", rawptr(nil))
}

// Polled every frame by an NSTimer. Reads Ctrl state + mouse pos globally
// (no key-window or Accessibility permission required).
tick :: proc "c" (user_data: rawptr, timer: rawptr) {
	ctrl :=
		bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_Control)) ||
		bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_RightControl))

	loc := msgSend(CGPoint, NSEvent, "mouseLocation")

	// "m" toggles annotation mode (press edge). While active, the left mouse
	// button draws magenta strokes instead of panning.
	context = runtime.default_context()
	annotate := bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_ANSI_M))
	if annotate && !g_annotate_down {
		g_annotate_on = !g_annotate_on
		fmt.printfln("[annotate] %s", g_annotate_on ? "on" : "off")
	}
	g_annotate_down = annotate

	// Click-and-drag to pan. Track the left mouse button globally and move
	// the content by the cursor delta while held. In annotation mode the left
	// button draws instead.
	pan := bool(CGEventSourceButtonState(kCGEventSourceStateCombined, kCGMouseButtonLeft))
	if g_annotate_on {
		if pan {
			c := screen_to_content(loc)
			if !g_anno_drawing {
				// New stroke on the press edge.
				append(&g_strokes, make([dynamic]CGPoint))
				g_anno_drawing = true
			}
			s := &g_strokes[len(g_strokes) - 1]
			append(s, c)
		} else {
			g_anno_drawing = false
		}
		g_pan_down = pan
		g_pan_last = loc
	} else {
		if pan {
			if g_pan_down {
				pan_by(loc.x - g_pan_last.x, loc.y - g_pan_last.y)
			}
			g_pan_last = loc
		}
		g_pan_down = pan
	}
	update_annotation()

	// "0" resets zoom, pan, and flip to the original view (press edge).
	zero := bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_ANSI_0))
	if zero && !g_zero_down {
		reset_view()
	}
	g_zero_down = zero

	// Option toggles the horizontal flip on the press edge, about the cursor.
	// moomer is often launched via an Option-containing hotkey, so ignore
	// Option until it has been released at least once.
	opt :=
		bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_Option)) ||
		bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_RightOption))
	if !opt {
		g_opt_armed = true
	}
	if g_opt_armed && opt && !g_opt_down {
		toggle_flip(loc)
	}
	g_opt_down = opt

	// Log only on state transitions so we don't spam every frame.
	if ctrl != g_ctrl_down {
		context = runtime.default_context()
		if ctrl {
			fmt.printfln("[ctrl] pressed - spotlight at (%.0f, %.0f)", loc.x, loc.y)
		} else {
			fmt.println("[ctrl] released - spotlight off")
		}
		g_ctrl_down = ctrl
	}

	update_spotlight(loc, ctrl)

	// Shift shows the real pixel coordinates under the cursor. Pressing "c"
	// while a selection is active copies that selection to the clipboard.
	left_shift := bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_Shift))
	right_shift := bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_RightShift))
	shift := left_shift || right_shift
	update_coords(loc, shift)

	// On the "c" press edge, crop+copy the current selection.
	copy := bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_ANSI_C))
	if copy && !g_copy_down && shift {
		copy_selection()
	}
	// Shift + "a" saves the current selection to a timestamped PNG file and
	// copies its path to the clipboard.
	save := bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_ANSI_A))
	if save && !g_save_down && shift {
		save_selection()
	}
	g_save_down = save
	// Without Shift, "c" copies the color of the pixel under the cursor.
	if copy && !g_pick_down && !shift {
		copy_pixel_color(loc)
	}
	g_pick_down = copy
	g_copy_down = copy

	// "g" toggles the pixel-edge grid (press edge). It's redrawn every frame so
	// it tracks zoom/pan changes.
	grid := bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_ANSI_G))
	if grid && !g_grid_down {
		g_grid_on = !g_grid_on
	}
	g_grid_down = grid
	update_grid()
}

main :: proc() {
	if !CGPreflightScreenCaptureAccess() {
		// Triggers the system permission prompt immediately at startup.
		if !CGRequestScreenCaptureAccess() {
			fmt.eprintln("Screen Recording permission denied. Grant it in System Settings > Privacy & Security > Screen Recording, then relaunch.")
			os.exit(1)
		}
	}
	display := CGMainDisplayID()
	image := CGDisplayCreateImage(display)
	if image == nil {
		fmt.eprintln("Failed to capture screen (screen recording permission may be required).")
		os.exit(1)
	}
	bounds := CGDisplayBounds(display)
	g_image = image

	// NSApplication *app = [NSApplication sharedApplication];
	app := msgSend(^NSApplication, NSApplication, "sharedApplication")
	msgSend(nil, app, "setActivationPolicy:", NSApplicationActivationPolicyRegular)

	// NSWindow *window = [[NSWindow alloc] initWithContentRect:styleMask:backing:defer:];
	win := msgSend(^NSWindow, NSWindow, "alloc")
	win = msgSend(
		^NSWindow,
		win,
		"initWithContentRect:styleMask:backing:defer:",
		bounds,
		NSWindowStyleMaskBorderless,
		NSBackingStoreBuffered,
		NS.BOOL(false),
	)

	msgSend(nil, win, "setLevel:", NSScreenSaverWindowLevel)
	msgSend(nil, win, "setOpaque:", NS.BOOL(true))
	msgSend(nil, win, "setAcceptsMouseMovedEvents:", NS.BOOL(true))

	frame := CGRect{{0, 0}, {bounds.size.width, bounds.size.height}}

	// The zoomable content is a single CALayer whose `contents` is the captured
	// CGImage. Using one layer (instead of an NSImageView nested inside the
	// transformed container) means there is no parent/child compositing step to
	// re-sample and smooth the pixels — the nearest-neighbour magnification
	// filter on this one layer is authoritative when the zoom transform enlarges
	// it, so zoomed-in pixels stay crisp squares.

	// Dimming overlay lives in its own layer-hosting NSView placed above the
	// image view. NSImageView manages its own backing layer, so adding a
	// sublayer there doesn't reliably render; a dedicated overlay view does.
	g_bounds = CGRect{{0, 0}, {bounds.size.width, bounds.size.height}}

	overlay := msgSend(^CAShapeLayer, CAShapeLayer, "alloc")
	overlay = msgSend(^CAShapeLayer, overlay, "init")
	msgSend(nil, overlay, "setFrame:", g_bounds)
	black := CGColorCreateGenericRGB(0, 0, 0, 0.75)
	msgSend(nil, overlay, "setFillColor:", black)
	CGColorRelease(black)
	msgSend(nil, overlay, "setFillRule:", NS.AT("even-odd")) // kCAFillRuleEvenOdd
	msgSend(nil, overlay, "setHidden:", NS.BOOL(true))
	g_overlay = overlay

	// Faint outline stroked only around the spotlight circle, so the highlight
	// stays visible on a completely black background.
	spot_ring := msgSend(^CAShapeLayer, CAShapeLayer, "alloc")
	spot_ring = msgSend(^CAShapeLayer, spot_ring, "init")
	msgSend(nil, spot_ring, "setFrame:", g_bounds)
	ring_clear := CGColorCreateGenericRGB(0, 0, 0, 0)
	msgSend(nil, spot_ring, "setFillColor:", ring_clear)
	CGColorRelease(ring_clear)
	ring_stroke := CGColorCreateGenericRGB(1, 1, 1, 0.18)
	msgSend(nil, spot_ring, "setStrokeColor:", ring_stroke)
	CGColorRelease(ring_stroke)
	msgSend(nil, spot_ring, "setLineWidth:", CGFloat(1))
	msgSend(nil, spot_ring, "setHidden:", NS.BOOL(true))
	g_spot_ring = spot_ring

	// Dark rounded background box hosting the readout text, so the white text
	// is readable on any background (including white).
	g_img_height = CGFloat(CGImageGetHeight(image))
	g_backing_scale = g_img_height / g_bounds.size.height
	box := msgSend(^CALayer, CALayer, "alloc")
	box = msgSend(^CALayer, box, "init")
	bg := CGColorCreateGenericRGB(0, 0, 0, 0.7)
	msgSend(nil, box, "setBackgroundColor:", bg)
	CGColorRelease(bg)
	msgSend(nil, box, "setCornerRadius:", CGFloat(4))
	msgSend(nil, box, "setHidden:", NS.BOOL(true))
	g_coord_layer = box

	coord := msgSend(^CATextLayer, CATextLayer, "alloc")
	coord = msgSend(^CATextLayer, coord, "init")
	msgSend(nil, coord, "setFontSize:", CGFloat(16))
	white := CGColorCreateGenericRGB(1, 1, 1, 1)
	msgSend(nil, coord, "setForegroundColor:", white)
	CGColorRelease(white)
	msgSend(nil, coord, "setAlignmentMode:", NS.AT("center"))
	msgSend(nil, coord, "setWrapped:", NS.BOOL(true))
	msgSend(nil, box, "addSublayer:", coord)
	g_coord_text = coord

	// Shape layer that outlines the dragged area while Shift is held.
	rect := msgSend(^CAShapeLayer, CAShapeLayer, "alloc")
	rect = msgSend(^CAShapeLayer, rect, "init")
	msgSend(nil, rect, "setFrame:", g_bounds)
	clear := CGColorCreateGenericRGB(0, 0, 0, 0)
	msgSend(nil, rect, "setFillColor:", clear)
	CGColorRelease(clear)
	stroke := CGColorCreateGenericRGB(1, 0.3, 0.1, 1)
	msgSend(nil, rect, "setStrokeColor:", stroke)
	CGColorRelease(stroke)
	msgSend(nil, rect, "setLineWidth:", CGFloat(2))
	msgSend(nil, rect, "setHidden:", NS.BOOL(true))
	g_rect_layer = rect

	// Shape layer that draws the thin light-grey pixel-edge grid.
	grid := msgSend(^CAShapeLayer, CAShapeLayer, "alloc")
	grid = msgSend(^CAShapeLayer, grid, "init")
	msgSend(nil, grid, "setFrame:", g_bounds)
	grid_clear := CGColorCreateGenericRGB(0, 0, 0, 0)
	msgSend(nil, grid, "setFillColor:", grid_clear)
	CGColorRelease(grid_clear)
	grid_stroke := CGColorCreateGenericRGB(0.8, 0.8, 0.8, 0.5)
	msgSend(nil, grid, "setStrokeColor:", grid_stroke)
	CGColorRelease(grid_stroke)
	msgSend(nil, grid, "setLineWidth:", CGFloat(1))
	msgSend(nil, grid, "setHidden:", NS.BOOL(true))
	g_grid_layer = grid

	// Shape layer that draws magenta annotation strokes. Drawn in screen space
	// (rebuilt each frame) so the 2px width stays constant while the strokes
	// follow the image through zoom/pan.
	anno := msgSend(^CAShapeLayer, CAShapeLayer, "alloc")
	anno = msgSend(^CAShapeLayer, anno, "init")
	msgSend(nil, anno, "setFrame:", g_bounds)
	anno_clear := CGColorCreateGenericRGB(0, 0, 0, 0)
	msgSend(nil, anno, "setFillColor:", anno_clear)
	CGColorRelease(anno_clear)
	magenta := CGColorCreateGenericRGB(1, 0, 1, 1)
	msgSend(nil, anno, "setStrokeColor:", magenta)
	CGColorRelease(magenta)
	msgSend(nil, anno, "setLineWidth:", CGFloat(2))
	msgSend(nil, anno, "setLineCap:", NS.AT("round"))
	msgSend(nil, anno, "setLineJoin:", NS.AT("round"))
	msgSend(nil, anno, "setHidden:", NS.BOOL(true))
	g_anno_layer = anno

	overlay_view := msgSend(^NSView, NSView, "alloc")
	overlay_view = msgSend(^NSView, overlay_view, "initWithFrame:", frame)
	// Plain backing layer that hosts BOTH the spotlight shape layer and the
	// coord text layer as siblings. (Previously coord was a child of `overlay`,
	// which is hidden whenever the spotlight is off, so it never showed.)
	msgSend(nil, overlay_view, "setWantsLayer:", NS.BOOL(true))
	host := msgSend(^CALayer, overlay_view, "layer")
	msgSend(nil, host, "addSublayer:", overlay)
	msgSend(nil, host, "addSublayer:", spot_ring)
	msgSend(nil, host, "addSublayer:", grid)
	msgSend(nil, host, "addSublayer:", anno)
	msgSend(nil, host, "addSublayer:", rect)
	msgSend(nil, host, "addSublayer:", box)

	// Container hosts the single content layer whose `contents` is the capture.
	container := msgSend(^NSView, NSView, "alloc")
	container = msgSend(^NSView, container, "initWithFrame:", frame)
	// Make the container layer-backed so we can transform its layer for zoom.
	msgSend(nil, container, "setWantsLayer:", NS.BOOL(true))
	content_layer := msgSend(^CALayer, container, "layer")
	// Put the full-resolution CGImage directly on the layer. CoreAnimation maps
	// its native pixels across the layer bounds; no NSImageView resample step.
	msgSend(nil, content_layer, "setContents:", image)
	// Anchor at bottom-left origin so our transform math (matching
	// NSEvent.mouseLocation) applies directly.
	msgSend(nil, content_layer, "setAnchorPoint:", CGPoint{0, 0})
	msgSend(nil, content_layer, "setFrame:", frame)
	// Nearest-neighbour so zoomed-in pixels stay crisp squares instead of
	// getting bilinear-smoothed.
	msgSend(nil, content_layer, "setMagnificationFilter:", NS.AT("nearest"))
	msgSend(nil, content_layer, "setMinificationFilter:", NS.AT("nearest"))
	g_content_layer = content_layer

	// Root view holds the zoomable container with the (non-zoomed) spotlight
	// overlay on top. Keeping the overlay outside the container means the
	// spotlight is never scaled, so it stays a constant on-screen size.
	root := msgSend(^NSView, NSView, "alloc")
	root = msgSend(^NSView, root, "initWithFrame:", frame)
	msgSend(nil, root, "addSubview:", container)
	msgSend(nil, root, "addSubview:", overlay_view)

	msgSend(nil, win, "setContentView:", root)
	msgSend(nil, win, "makeKeyAndOrderFront:", rawptr(nil))
	msgSend(nil, app, "activateIgnoringOtherApps:", NS.BOOL(true))

	// Scroll-wheel zoom via a local event monitor.
	BLOCK_IS_GLOBAL :: u32(1) << 28
	scroll_block = Block_Literal {
		isa        = &_NSConcreteGlobalBlock,
		flags      = BLOCK_IS_GLOBAL,
		invoke     = rawptr(scroll_block_invoke),
		descriptor = &scroll_block_descriptor,
		user_proc  = rawptr(scroll_handler),
		user_data  = nil,
	}
	msgSend(
		nil,
		NSEvent,
		"addLocalMonitorForEventsMatchingMask:handler:",
		NSEventMaskScrollWheel,
		&scroll_block,
	)

	// Escape (and any key) via an event monitor so fast single taps are never
	// missed the way polling can miss them.
	key_block = Block_Literal {
		isa        = &_NSConcreteGlobalBlock,
		flags      = BLOCK_IS_GLOBAL,
		invoke     = rawptr(key_block_invoke),
		descriptor = &scroll_block_descriptor,
		user_proc  = rawptr(key_handler),
		user_data  = nil,
	}
	msgSend(
		nil,
		NSEvent,
		"addLocalMonitorForEventsMatchingMask:handler:",
		NSEventMaskKeyDown,
		&key_block,
	)

	// Spotlight tracking via a polling timer (~60 fps). Escape/keys are now
	// event-driven, so polling only drives spotlight/mouse tracking.
	tick_block := NS.Block_createGlobalWithParam(nil, tick)
	timer := msgSend(
		^NSTimer,
		NSTimer,
		"timerWithTimeInterval:repeats:block:",
		CGFloat(1.0 / 60.0),
		NS.BOOL(true),
		tick_block,
	)
	// Add to the run loop in common modes so it fires during tracking too.
	run_loop := msgSend(^NSRunLoop, NSRunLoop, "mainRunLoop")
	msgSend(nil, run_loop, "addTimer:forMode:", timer, NS.AT("kCFRunLoopCommonModes"))

	// Note: g_image is intentionally not released here; it is retained by the
	// content layer and reused to crop the Shift selection onto the clipboard.

	msgSend(nil, app, "run")
}
