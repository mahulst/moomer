package main

import "core:fmt"
import "core:os"
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
	CGDisplayCreateImage :: proc "c" (display: CGDirectDisplayID) -> CGImageRef ---
	CGDisplayBounds :: proc "c" (display: CGDirectDisplayID) -> CGRect ---
	CGImageRelease :: proc "c" (image: CGImageRef) ---

	CGPathCreateMutable :: proc "c" () -> CGMutablePathRef ---
	CGPathAddRect :: proc "c" (path: CGMutablePathRef, m: rawptr, rect: CGRect) ---
	CGPathAddEllipseInRect :: proc "c" (path: CGMutablePathRef, m: rawptr, rect: CGRect) ---
	CGPathRelease :: proc "c" (path: CGPathRef) ---

	CGColorCreateGenericRGB :: proc "c" (r, g, b, a: CGFloat) -> CGColorRef ---
	CGColorRelease :: proc "c" (color: CGColorRef) ---

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
kCGEventSourceStateCombined :: i32(0)
kCGMouseButtonLeft :: u32(0)

g_spotlight_radius: CGFloat = 100
MIN_RADIUS :: CGFloat(20)
MAX_RADIUS :: CGFloat(600)

// Globals used by the event handlers.
g_overlay: ^CAShapeLayer // the dimming layer
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

update_spotlight :: proc "c" (mouse: CGPoint, visible: bool) {
	// Disable implicit animations for instant, no-animation updates.
	msgSend(nil, CATransaction, "begin")
	msgSend(nil, CATransaction, "setDisableActions:", NS.BOOL(true))

	if !visible {
		msgSend(nil, g_overlay, "setHidden:", NS.BOOL(true))
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
	CGPathRelease(path)

	msgSend(nil, CATransaction, "commit")
}

dismiss_handler :: proc "c" (user_data: rawptr, event: rawptr) {
	app := msgSend(^NSApplication, NSApplication, "sharedApplication")
	msgSend(nil, app, "terminate:", rawptr(nil))
}

// Polled every frame by an NSTimer. Reads Ctrl state + mouse pos globally
// (no key-window or Accessibility permission required).
tick :: proc "c" (user_data: rawptr, timer: rawptr) {
	// Quit on Escape.
	if bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_Escape)) {
		app := msgSend(^NSApplication, NSApplication, "sharedApplication")
		msgSend(nil, app, "terminate:", rawptr(nil))
		return
	}

	ctrl :=
		bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_Control)) ||
		bool(CGEventSourceKeyState(kCGEventSourceStateCombined, kVK_RightControl))

	loc := msgSend(CGPoint, NSEvent, "mouseLocation")

	// Click-and-drag to pan. Track the left mouse button globally and move
	// the content by the cursor delta while held.
	pan := bool(CGEventSourceButtonState(kCGEventSourceStateCombined, kCGMouseButtonLeft))
	if pan {
		if g_pan_down {
			pan_by(loc.x - g_pan_last.x, loc.y - g_pan_last.y)
		}
		g_pan_last = loc
	}
	g_pan_down = pan

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
}

main :: proc() {
	display := CGMainDisplayID()
	image := CGDisplayCreateImage(display)
	if image == nil {
		fmt.eprintln("Failed to capture screen (screen recording permission may be required).")
		os.exit(1)
	}
	bounds := CGDisplayBounds(display)

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

	// NSImageView *view = [[NSImageView alloc] initWithFrame:frame];
	frame := CGRect{{0, 0}, {bounds.size.width, bounds.size.height}}
	view := msgSend(^NSImageView, NSImageView, "alloc")
	view = msgSend(^NSImageView, view, "initWithFrame:", frame)

	// NSImage *img = [[NSImage alloc] initWithCGImage:image size:NSZeroSize];
	nsimg := msgSend(^NSImage, NSImage, "alloc")
	nsimg = msgSend(^NSImage, nsimg, "initWithCGImage:size:", image, CGSize{0, 0})

	msgSend(nil, view, "setImage:", nsimg)
	msgSend(nil, view, "setImageScaling:", NSImageScaleAxesIndependently)
	// Layer-back the image view and use nearest-neighbour so the screenshot
	// isn't bilinear-smoothed when the zoom transform enlarges it.
	msgSend(nil, view, "setWantsLayer:", NS.BOOL(true))
	img_layer := msgSend(^CALayer, view, "layer")
	msgSend(nil, img_layer, "setMagnificationFilter:", NS.AT("nearest"))
	msgSend(nil, img_layer, "setMinificationFilter:", NS.AT("nearest"))

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

	overlay_view := msgSend(^NSView, NSView, "alloc")
	overlay_view = msgSend(^NSView, overlay_view, "initWithFrame:", frame)
	// Layer-hosting: assign the layer BEFORE wantsLayer so it hosts our layer.
	msgSend(nil, overlay_view, "setLayer:", overlay)
	msgSend(nil, overlay_view, "setWantsLayer:", NS.BOOL(true))

	// Container holds only the (zoomable) image view.
	container := msgSend(^NSView, NSView, "alloc")
	container = msgSend(^NSView, container, "initWithFrame:", frame)
	msgSend(nil, container, "addSubview:", view)
	// Make the container layer-backed so we can transform its layer for zoom.
	msgSend(nil, container, "setWantsLayer:", NS.BOOL(true))
	content_layer := msgSend(^CALayer, container, "layer")
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

	// Spotlight tracking via a polling timer (~60 fps). Works regardless of
	// key-window status and needs no Accessibility permission.
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

	CGImageRelease(image)

	msgSend(nil, app, "run")
}
