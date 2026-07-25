package main

// moomer launcher: a menu-bar-only (accessory) app that owns a global hotkey
// and a status-item menu. On hotkey press or "Capture Screen" click it spawns
// the standalone `moomer` capture binary as a fresh subprocess. The capture
// tool itself is left completely untouched (see ../screenshot.odin).

import "core:fmt"
import "core:os"
import os2 "core:os/os2"
import "core:path/filepath"
import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

foreign import AppKit "system:AppKit.framework"
foreign import Carbon "system:Carbon.framework"

msgSend :: intrinsics.objc_send

// --- AppKit classes we talk to ---
@(objc_class = "NSApplication")
NSApplication :: struct {using _: NS.Object}
@(objc_class = "NSStatusBar")
NSStatusBar :: struct {using _: NS.Object}
@(objc_class = "NSStatusItem")
NSStatusItem :: struct {using _: NS.Object}
@(objc_class = "NSStatusBarButton")
NSStatusBarButton :: struct {using _: NS.Object}
@(objc_class = "NSMenu")
NSMenu :: struct {using _: NS.Object}
@(objc_class = "NSMenuItem")
NSMenuItem :: struct {using _: NS.Object}
@(objc_class = "NSObject")
NSObject :: struct {using _: NS.Object}
@(objc_class = "NSImage")
NSImage :: struct {using _: NS.Object}
@(objc_class = "NSBundle")
NSBundle :: struct {using _: NS.Object}

NSApplicationActivationPolicyAccessory :: NS.Integer(1)
NSVariableStatusItemLength :: NS.Float(-1)

// --- Carbon hotkey API ---
OSStatus :: i32
OSType :: u32
EventHotKeyRef :: rawptr
EventHandlerRef :: rawptr
EventTargetRef :: rawptr
EventRef :: rawptr
EventHandlerCallRef :: rawptr

EventHotKeyID :: struct {
	signature: OSType,
	id:        u32,
}

EventTypeSpec :: struct {
	eventClass: OSType,
	eventKind:  u32,
}

kEventClassKeyboard :: OSType(0x6b657962) // 'keyb'
kEventHotKeyPressed :: u32(5)

// Carbon modifier masks (Events.h)
cmdKey :: u32(1) << 8
shiftKey :: u32(1) << 9
optionKey :: u32(1) << 11
controlKey :: u32(1) << 12

// Virtual keycode for the "8" key.
kVK_ANSI_8 :: u32(0x1C)

EventHandlerUPP :: proc "c" (nextHandler: EventHandlerCallRef, event: EventRef, userData: rawptr) -> OSStatus

foreign Carbon {
	RegisterEventHotKey :: proc "c" (keyCode: u32, modifiers: u32, hotKeyID: EventHotKeyID, target: EventTargetRef, options: u32, outRef: ^EventHotKeyRef) -> OSStatus ---
	GetApplicationEventTarget :: proc "c" () -> EventTargetRef ---
	InstallEventHandler :: proc "c" (target: EventTargetRef, handler: EventHandlerUPP, numTypes: u32, list: [^]EventTypeSpec, userData: rawptr, outRef: ^EventHandlerRef) -> OSStatus ---
}

// Absolute path to the moomer capture binary, resolved once at startup.
g_moomer_path: string

// Spawn the capture tool as a detached subprocess. Each invocation grabs a
// fresh screenshot and shows its own overlay; it quits itself on Esc.
spawn_moomer :: proc() {
	if g_moomer_path == "" {
		fmt.eprintln("moomer binary not found")
		return
	}
	_, err := os2.process_start({
		command = {g_moomer_path},
	})
	if err != nil {
		fmt.eprintfln("failed to launch moomer: %v", err)
	}
}

// --- Menu / hotkey callbacks ---

// objc method: -(void)capture:(id)sender
capture_action :: proc "c" (self: NS.id, cmd: NS.SEL, sender: NS.id) {
	context = g_ctx
	spawn_moomer()
}

// objc method: -(void)quit:(id)sender
quit_action :: proc "c" (self: NS.id, cmd: NS.SEL, sender: NS.id) {
	app := msgSend(^NSApplication, NSApplication, "sharedApplication")
	msgSend(nil, app, "terminate:", rawptr(nil))
}

// Carbon hotkey handler: fired on our registered global hotkey.
hotkey_handler :: proc "c" (next: EventHandlerCallRef, event: EventRef, userData: rawptr) -> OSStatus {
	context = g_ctx
	spawn_moomer()
	return 0
}

g_ctx: runtime_context

// Alias so the "c" callbacks can restore an Odin context.
import "base:runtime"
runtime_context :: runtime.Context

// Build "MoomerTarget", an NSObject subclass exposing capture:/quit:, and
// return one instance to serve as the menu items' target.
make_menu_target :: proc() -> ^NSObject {
	nsobject := NS.objc_lookUpClass("NSObject")
	cls := NS.objc_allocateClassPair(nsobject, "MoomerTarget", 0)

	// "v@:@" = returns void, args (self id, SEL, id sender)
	NS.class_addMethod(cls, NS.sel_registerName("capture:"), auto_cast capture_action, "v@:@")
	NS.class_addMethod(cls, NS.sel_registerName("quit:"), auto_cast quit_action, "v@:@")
	NS.objc_registerClassPair(cls)

	// class_createInstance avoids needing typed alloc/init msgSends on a class
	// that doesn't exist at compile time.
	inst := NS.class_createInstance(cls, 0)
	return cast(^NSObject)inst
}

nsstr :: proc(s: cstring) -> ^NS.String {
	return msgSend(^NS.String, NS.String, "stringWithUTF8String:", s)
}

// Locate the menu-bar icon PNG. Inside the .app it's copied to
// Contents/Resources/menubar-icon.png (a sibling of MacOS/); during a plain
// side-by-side dev build it's the black template at icons/cow-icon-light-32.png.
resolve_icon_path :: proc() -> (string, bool) {
	exe, err := os2.get_executable_path(context.allocator)
	if err != nil {
		return "", false
	}
	macos_dir := filepath.dir(exe) // .../Contents/MacOS  or  repo root
	// Bundle layout: ../Resources/menubar-icon.png
	bundle_icon := filepath.join({filepath.dir(macos_dir), "Resources", "menubar-icon.png"})
	if os.exists(bundle_icon) {
		return bundle_icon, true
	}
	// Dev layout: icons/ beside the launcher binary's project root.
	dev_icon := filepath.join({macos_dir, "icons", "cow-icon-light-32.png"})
	if os.exists(dev_icon) {
		return dev_icon, true
	}
	return "", false
}

// Load the cow as a template image (macOS recolors it for light/dark menu bars
// using only its alpha), or fall back to a text title if it can't be found.
set_status_icon :: proc(button: ^NSStatusBarButton) {
	path, ok := resolve_icon_path()
	if !ok {
		msgSend(nil, button, "setTitle:", nsstr("moo"))
		return
	}
	img := msgSend(^NSImage, NSImage, "alloc")
	cpath := fmt.ctprintf("%s", path)
	img = msgSend(^NSImage, img, "initWithContentsOfFile:", nsstr(cpath))
	if img == nil {
		msgSend(nil, button, "setTitle:", nsstr("moo"))
		return
	}
	// Constrain to a crisp menu-bar height; templating handles the coloring.
	msgSend(nil, img, "setSize:", NS.Size{18, 18})
	msgSend(nil, img, "setTemplate:", NS.BOOL(true))
	msgSend(nil, button, "setImage:", img)
}

// Locate the moomer binary. Prefer a sibling of this launcher executable
// (works both for `Contents/MacOS/moomer` inside the .app bundle and for a
// plain side-by-side build), then fall back to PATH-relative "moomer".
resolve_moomer_path :: proc() -> string {
	exe, err := os2.get_executable_path(context.allocator)
	if err == nil {
		dir := filepath.dir(exe)
		cand := filepath.join({dir, "moomer"})
		if os.exists(cand) {
			return cand
		}
	}
	return "moomer"
}

main :: proc() {
	g_ctx = context
	g_moomer_path = resolve_moomer_path()

	app := msgSend(^NSApplication, NSApplication, "sharedApplication")
	// Accessory: no Dock icon, no menu bar app menu, just the status item.
	msgSend(nil, app, "setActivationPolicy:", NSApplicationActivationPolicyAccessory)

	// Status-bar item with a text/emoji title (an icon can be set later).
	bar := msgSend(^NSStatusBar, NSStatusBar, "systemStatusBar")
	item := msgSend(^NSStatusItem, bar, "statusItemWithLength:", NSVariableStatusItemLength)
	button := msgSend(^NSStatusBarButton, item, "button")
	set_status_icon(button)

	target := make_menu_target()

	menu := msgSend(^NSMenu, NSMenu, "alloc")
	menu = msgSend(^NSMenu, menu, "init")

	// "Capture Screen" with a visible Cmd+Shift+2 shortcut hint.
	cap_item := msgSend(^NSMenuItem, NSMenuItem, "alloc")
	cap_item = msgSend(
		^NSMenuItem, cap_item,
		"initWithTitle:action:keyEquivalent:",
		nsstr("Capture Screen"), NS.sel_registerName("capture:"), nsstr("8"),
	)
	// keyEquivalentModifierMask: NSEventModifierFlagCommand(1<<20)|Shift(1<<17)
	msgSend(nil, cap_item, "setKeyEquivalentModifierMask:", NS.UInteger(1 << 20 | 1 << 17))
	msgSend(nil, cap_item, "setTarget:", target)
	msgSend(nil, menu, "addItem:", cap_item)

	sep := msgSend(^NSMenuItem, NSMenuItem, "separatorItem")
	msgSend(nil, menu, "addItem:", sep)

	quit_item := msgSend(^NSMenuItem, NSMenuItem, "alloc")
	quit_item = msgSend(
		^NSMenuItem, quit_item,
		"initWithTitle:action:keyEquivalent:",
		nsstr("Quit moomer"), NS.sel_registerName("quit:"), nsstr("q"),
	)
	msgSend(nil, quit_item, "setTarget:", target)
	msgSend(nil, menu, "addItem:", quit_item)

	msgSend(nil, item, "setMenu:", menu)

	// Global hotkey: Cmd+Shift+8.
	spec := EventTypeSpec{kEventClassKeyboard, kEventHotKeyPressed}
	handler_ref: EventHandlerRef
	InstallEventHandler(
		GetApplicationEventTarget(), hotkey_handler, 1, &spec, nil, &handler_ref,
	)
	hk_id := EventHotKeyID{signature = 0x6d6f6f6d /* 'moom' */, id = 1}
	hk_ref: EventHotKeyRef
	status := RegisterEventHotKey(
		kVK_ANSI_8, cmdKey | shiftKey, hk_id, GetApplicationEventTarget(), 0, &hk_ref,
	)
	if status != 0 {
		fmt.eprintfln("failed to register hotkey (status %d)", status)
	}

	msgSend(nil, app, "run")
}
