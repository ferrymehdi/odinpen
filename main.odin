package main

import "base:runtime"
import "buffer"
import "config"
import "core/command"
import "core/keybind"
import "core/render"
import "core:fmt"
import "core:path/filepath"
import "core:strings"
import "inputline"
import "session"
import "sessionmanager"
import "tab"
import "vendor:OpenGL"
import "vendor:glfw"
import "window"

app_state :: struct {
	window:      glfw.WindowHandle,
	editor_app:  sessionmanager.session_manager,
	pending_key: keybind.key,
}

gl_major_version :: 3

gl_minor_version :: 3

glfw_to_keycode :: proc(key: i32) -> i32 {
	if key >= 'A' && key <= 'Z' {
		return key - 'A' + 'a'
	}
	return key
}

glfw_to_mods :: proc(mods: i32) -> keybind.modifiers {
	result := keybind.modifiers{}
	if mods & glfw.MOD_SHIFT != 0 {result += {.Shift}}
	if mods & glfw.MOD_CONTROL != 0 {result += {.Control}}
	if mods & glfw.MOD_ALT != 0 {result += {.Alt}}
	return result
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	if action != glfw.PRESS && action != glfw.REPEAT {
		return
	}

	context = runtime.default_context()
	context.user_ptr = glfw.GetWindowUserPointer(window)

	code := glfw_to_keycode(key)
	if code == 0 {
		return
	}

	k := keybind.key {
		code = code,
		mods = glfw_to_mods(mods),
	}
	switch code {
	case keybind.KEY_TAB:
		k.char = '\t'
	case keybind.KEY_ENTER:
		k.char = '\n'
	case keybind.KEY_BACKSPACE:
		k.char = '\b'
	}
	g_state := (^app_state)(context.user_ptr)
	dispatch_key(g_state, k)
}

char_callback :: proc "c" (window: glfw.WindowHandle, codepoint: rune) {
	context = runtime.default_context()
	context.user_ptr = glfw.GetWindowUserPointer(window)

	g_state := (^app_state)(context.user_ptr)
	if g_state.pending_key.code != 0 {
		g_state.pending_key.char = codepoint
		flush_pending_key(g_state)
	} else {
		k := keybind.key {
			code = 0,
			mods = {},
			char = codepoint,
		}
		dispatch_key(g_state, k)
	}
}

dispatch_key :: proc(state: ^app_state, key: keybind.key) -> bool {
	if state.pending_key.code != 0 {
		flush_pending_key(state)
	}

	is_printable := key.code >= 32 && key.code <= 126
	has_mods := key.mods & {.Control, .Alt} != {}

	if is_printable && !has_mods && key.char == 0 {
		state.pending_key = key
		return true
	}

	m := &state.editor_app

	if inputline.is_active() {
		handled := inputline.handle_key(key)
		if handled {
			return true
		}
	}

	inputline.set_message("")

	handled, process_session := sessionmanager.handle_key(m, key)
	if handled do return true
	if !process_session do return false

	s := sessionmanager.get_active_session(m)
	if s == nil do return false

	t := session.focused_tab(s)
	win := t != nil ? tab.focused_window(t) : nil

	if t != nil && tab.preview_handle_key(t, key) {
		return true
	}

	if win != nil && window.preview_handle_key(win, key) {
		return true
	}

	if win != nil && window.handle_key(win, key) {
		return true
	}

	if t != nil && tab.handle_key(t, key) {
		return true
	}

	if session.handle_key(s, key) {
		return true
	}


	return false
}

flush_pending_key :: proc(state: ^app_state) {
	k := state.pending_key
	state.pending_key = {}
	dispatch_key(state, k)
}

session_on_close :: proc(env: rawptr, s: ^session.session) {
	state := (^app_state)(env)
	if state == nil do return

	if len(state.editor_app.sessions) > 1 {
		sessionmanager.close_active_session(&state.editor_app)
	} else {
		glfw.SetWindowShouldClose(state.window, true)
	}
}

command_callback :: proc(env: rawptr, text: string) {
	state := (^app_state)(env)
	if len(text) > 0 {
		name, args := command.parse_command_line(text)
		if !sessionmanager.handle_command(&state.editor_app, name, args) {
			inputline.set_error(fmt.tprintf("Error: Not an editor command: %s", name))
		}
	}
}

main :: proc() {
	if !glfw.Init() {
		fmt.eprintln("Failed to initialize OpenGLFW")
		return
	}

	main_window := glfw.CreateWindow(640, 480, "Test", nil, nil)
	if main_window == nil {
		fmt.eprintln("Failed to create OpenGLFW window")
		glfw.Terminate()
		return
	}
	glfw.MakeContextCurrent(main_window)
	OpenGL.load_up_to(gl_major_version, gl_minor_version, glfw.gl_set_proc_address)

	r := render.renderer_state{}
	render.init(&r)

	state: app_state
	state.window = main_window
	sessionmanager.init(&state.editor_app, {session_on_close, &state})
	keybind.bind_single(&state.editor_app.key_binder, {char = ':'}, {proc(env: rawptr) -> bool {
			m := (^sessionmanager.session_manager)(env)
			s := sessionmanager.get_active_session(m)
			if s != nil {
				t := session.focused_tab(s)
				win := t != nil ? tab.focused_window(t) : nil
				if win != nil && window.get_mode(win) == .Normal {
					inputline.start_input(":", {command_callback, m})
					return true
				}
			}
			return false
		}, &state.editor_app})
	sessionmanager.new_session(&state.editor_app, "default", ".")

	context.user_ptr = &state
	glfw.SetWindowUserPointer(main_window, &state)

	glfw.SetKeyCallback(main_window, key_callback)
	glfw.SetCharCallback(main_window, char_callback)

	for !glfw.WindowShouldClose(main_window) {

		bg := config.global_config.colorscheme.bg
		OpenGL.ClearColor(bg[0], bg[1], bg[2], bg[3])
		OpenGL.Clear(OpenGL.COLOR_BUFFER_BIT)

		width, height := glfw.GetWindowSize(main_window)
		fw, fh := glfw.GetFramebufferSize(main_window)

		if width > 0 && height > 0 {
			OpenGL.Viewport(0, 0, fw, fh)
			render.begin_frame(&r)

			ortho := [16]f32 {
				2.0 / f32(width),
				0,
				0,
				0,
				0,
				-2.0 / f32(height),
				0,
				0,
				0,
				0,
				-1.0,
				0,
				-1.0,
				1.0,
				0,
				1.0,
			}
			dpi_scale := f32(fw) / f32(width)
			render.render_set_projection(&r, ortho, dpi_scale)

			screen_space := render.rect{0, 0, f32(width), f32(height)}
			remaining_space := screen_space

			session_inst := sessionmanager.get_active_session(&state.editor_app)
			if session_inst != nil {
				for t in session_inst.tabs {
					win := tab.focused_window(t)
					if win != nil && win.buffer != nil && len(win.buffer.path) > 0 {
						base := filepath.base(win.buffer.path)
						if t.name != base {
							delete(t.name)
							t.name = strings.clone(base)
						}
					}
				}

				remaining_space = inputline.draw(&r, screen_space)
			}

			sessionmanager.draw(&r, &state.editor_app, remaining_space)
			render.end_frame(&r)
		}

		glfw.PollEvents()
		free_all(context.temp_allocator)

		glfw.SwapBuffers(main_window)
	}

	sessionmanager.destroy(&state.editor_app)
	render.destroy(&r)
	glfw.DestroyWindow(main_window)
	glfw.Terminate()
}
