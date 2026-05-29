package finder

import "../core/keybind"
import "core:unicode/utf8"

setup_keybinds :: proc(ff: ^finder_state) {
	keybind.bind_single(&ff.key_binder, {code = keybind.KEY_ESCAPE}, {close_finder, ff})
	keybind.bind_single(&ff.key_binder, {code = 'p', mods = {.Control}}, {close_finder, ff})
	keybind.bind_single(&ff.key_binder, {code = keybind.KEY_DOWN}, {move_down, ff})
	keybind.bind_single(&ff.key_binder, {code = 'j', mods = {.Control}}, {move_down, ff})
	keybind.bind_single(&ff.key_binder, {code = keybind.KEY_UP}, {move_up, ff})
	keybind.bind_single(&ff.key_binder, {code = 'k', mods = {.Control}}, {move_up, ff})
	keybind.bind_single(&ff.key_binder, {code = keybind.KEY_ENTER}, {select_item, ff})
	keybind.bind_single(&ff.key_binder, {code = keybind.KEY_BACKSPACE}, {backspace, ff})
}

close_finder :: proc(env: rawptr) -> bool {
	ff := (^finder_state)(env)
	ff.should_close = true
	return true
}

move_down :: proc(env: rawptr) -> bool {
	ff := (^finder_state)(env)
	if len(ff.filtered) > 0 {
		ff.selected = (ff.selected + 1) % len(ff.filtered)
	}
	return true
}

move_up :: proc(env: rawptr) -> bool {
	ff := (^finder_state)(env)
	if len(ff.filtered) > 0 {
		ff.selected = (ff.selected - 1 + len(ff.filtered)) % len(ff.filtered)
	}
	return true
}

select_item :: proc(env: rawptr) -> bool {
	ff := (^finder_state)(env)
	if ff.selected >= 0 && ff.selected < len(ff.filtered) {
		match_item := ff.filtered[ff.selected]
		if ff.on_select.call != nil && ff.on_select.call(ff.on_select.env, match_item.item) {
			ff.should_close = true
		}
	}
	return true
}

backspace :: proc(env: rawptr) -> bool {
	ff := (^finder_state)(env)
	if len(ff.input) > 0 {
		str := string(ff.input[:])
		_, size := utf8.decode_last_rune_in_string(str)
		if size > 0 {
			resize(&ff.input, len(ff.input) - size)
			ff.cursor = len(ff.input)
			ff.selected = 0
			update_filter(ff)
		}
	}
	return true
}

handle_key :: proc(ff: ^finder_state, key: keybind.key) -> bool {
	if keybind.handle(&ff.key_binder, key) {
		return true
	}

	if key.char != 0 {
		buf, n := utf8.encode_rune(key.char)
		append(&ff.input, ..buf[:n])
		ff.cursor = len(ff.input)
		ff.selected = 0
		update_filter(ff)
		return true
	}

	return false
}
