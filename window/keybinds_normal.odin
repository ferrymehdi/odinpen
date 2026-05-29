package window

import "../core/keybind"

setup_normal_keybinds :: proc(w: ^window) {
	keybind.bind_single(&w.normal_kb, {code = keybind.KEY_UP}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_cursor(w, -1, 0)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {code = keybind.KEY_DOWN}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_cursor(w, 1, 0)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {code = keybind.KEY_LEFT}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_cursor(w, 0, -1)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {code = keybind.KEY_RIGHT}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_cursor(w, 0, 1)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'h'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_cursor(w, 0, -1)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'j'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_cursor(w, 1, 0)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'k'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_cursor(w, -1, 0)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'l'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_cursor(w, 0, 1)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'i'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			w.mode = .Insert
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'a'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			w.mode = .Insert
			if w.buffer != nil {
				w.cursor_col += 1
				clamp_cursor(w)
			}
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'A'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			w.mode = .Insert
			if w.buffer != nil {
				move_to_end_of_line(w)
				w.cursor_col += 1
				clamp_cursor(w)
			}
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'I'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			if w.buffer != nil {
				move_to_first_non_blank(w)
			}
			w.mode = .Insert
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'o'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			open_line_below(w)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'O'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			open_line_above(w)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'D'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			delete_to_end_of_line(w)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'J'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			join_lines(w)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {code = '=', mods = {.Control}}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			new_size := get_font_size(w) + 2.0
			if new_size > 256.0 {
				new_size = 256.0
			}
			set_font_size(w, new_size)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {code = '-', mods = {.Control}}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			new_size := get_font_size(w) - 2.0
			if new_size < 4.0 {
				new_size = 4.0
			}
			set_font_size(w, new_size)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = '-'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			toggle_explorer(w)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'w'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_to_next_word(w, false)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'W'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_to_next_word(w, true)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'b'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_to_prev_word(w, false)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'B'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_to_prev_word(w, true)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'e'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_to_end_of_word(w, false)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'E'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_to_end_of_word(w, true)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'x'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			delete_char_under_cursor(w)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = '0'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_to_start_of_line(w)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = '$'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_to_end_of_line(w)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = '^'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_to_first_non_blank(w)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {char = 'G'}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_to_last_line(w)
			return true
		}, w})

	keybind.bind_single(&w.normal_kb, {code = 'p', mods = {.Control}}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			toggle_finder(w, ".")
			return true
		}, w})

	keybind.bind_keys(
		&w.normal_kb,
		[]keybind.key{{char = 'g'}, {char = 'g'}},
		{proc(env: rawptr) -> bool {
				w := (^window)(env)
				move_to_first_line(w)
				return true
			}, w},
	)

	keybind.bind_keys(
		&w.normal_kb,
		[]keybind.key{{char = 'd'}, {char = 'd'}},
		{proc(env: rawptr) -> bool {
				w := (^window)(env)
				delete_line(w)
				return true
			}, w},
	)

	keybind.bind_keys(
		&w.normal_kb,
		[]keybind.key{{char = 'd'}, {char = 'w'}},
		{proc(env: rawptr) -> bool {
				w := (^window)(env)
				delete_word(w)
				return true
			}, w},
	)
}
