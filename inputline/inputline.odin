package inputline

import "../core/keybind"
import "core:strings"
import "core:unicode/utf8"

handler :: #type proc(env: rawptr, text: string)

Callback :: struct {
	call: handler,
	env:  rawptr,
}

input_line :: struct {
	input:      [dynamic]u8,
	message:    string,
	is_active:  bool,
	is_error:   bool,
	callback:   Callback,
	key_binder: keybind.key_binder,
}

global_input_line: input_line

init :: proc() {
	global_input_line.input = make([dynamic]u8, 0, 32)
	global_input_line.message = ""
	global_input_line.is_active = false
	global_input_line.is_error = false
	global_input_line.callback = {}

	keybind.init(&global_input_line.key_binder)
	setup_keybinds(&global_input_line.key_binder)
}

destroy :: proc() {
	delete(global_input_line.input)
	if len(global_input_line.message) > 0 {
		delete(global_input_line.message)
	}
	keybind.destroy(&global_input_line.key_binder)
}

clear_input :: proc() {
	clear(&global_input_line.input)
}

set_message :: proc(msg: string) {
	if len(global_input_line.message) > 0 {
		delete(global_input_line.message)
	}
	global_input_line.is_error = false
	if len(msg) > 0 {
		global_input_line.message = strings.clone(msg)
	} else {
		global_input_line.message = ""
	}
}

set_error :: proc(err: string) {
	if len(global_input_line.message) > 0 {
		delete(global_input_line.message)
	}
	global_input_line.is_error = true
	if len(err) > 0 {
		global_input_line.message = strings.clone(err)
	} else {
		global_input_line.message = ""
	}
}

start_input :: proc(prompt: string, cb: Callback = {}) {
	global_input_line.is_active = true
	global_input_line.callback = cb
	if len(global_input_line.message) > 0 {
		delete(global_input_line.message)
	}
	global_input_line.message = strings.clone(prompt)
	clear_input()
}

exit :: proc() {
	global_input_line.is_active = false
	global_input_line.callback = {}
	if len(global_input_line.message) > 0 {
		delete(global_input_line.message)
		global_input_line.message = ""
	}
	clear_input()
}

is_active :: proc() -> bool {
	return global_input_line.is_active
}

setup_keybinds :: proc(kb: ^keybind.key_binder) {
	keybind.bind_single(kb, {code = keybind.KEY_ESCAPE}, {cancel_input, nil})
	keybind.bind_single(kb, {code = keybind.KEY_BACKSPACE}, {backspace_input, nil})
	keybind.bind_single(kb, {code = keybind.KEY_ENTER}, {commit_input, nil})
}

cancel_input :: proc(env: rawptr) -> bool {
	exit()
	return true
}

backspace_input :: proc(env: rawptr) -> bool {
	if len(global_input_line.input) > 0 {
		str := string(global_input_line.input[:])
		_, size := utf8.decode_last_rune_in_string(str)
		if size > 0 {
			resize(&global_input_line.input, len(global_input_line.input) - size)
		}
	}
	if len(global_input_line.input) == 0 {
		exit()
	}
	return true
}

commit_input :: proc(env: rawptr) -> bool {
	committed_text := strings.clone(string(global_input_line.input[:]), context.temp_allocator)
	cb := global_input_line.callback
	exit()
	if cb.call != nil {
		cb.call(cb.env, committed_text)
	}
	return true
}

handle_key :: proc(key: keybind.key) -> bool {
	if !global_input_line.is_active do return false

	if keybind.handle(&global_input_line.key_binder, key) {
		return true
	}

	if key.char != 0 {
		buf, n := utf8.encode_rune(key.char)
		append(&global_input_line.input, ..buf[:n])
		return true
	}

	return true
}
