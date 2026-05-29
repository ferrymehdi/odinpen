package window

import "../buffer"
import "../core/keybind"

setup_insert_keybinds :: proc(w: ^window) {
	keybind.bind_single(&w.insert_kb, {code = keybind.KEY_ESCAPE}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			w.mode = .Normal
			if w.cursor_col > 0 {
				w.cursor_col -= 1
			}
			clamp_cursor(w)
			return true
		}, w})

	keybind.bind_single(&w.insert_kb, {code = keybind.KEY_ENTER}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			if w.buffer == nil do return false

			line := buffer.get_line(w.buffer, w.cursor_line)
			col_limit := min(w.cursor_col, len(line))
			line_to_cursor := line[:col_limit]

			indent_len := get_line_indent(line_to_cursor)

			offset := get_cursor_offset(w)
			buffer.insert(w.buffer, offset, "\n")
			if indent_len > 0 {
				buffer.insert(w.buffer, offset + 1, line_to_cursor[:indent_len])
			}

			w.cursor_line += 1
			w.cursor_col = indent_len
			w.cursor_off = offset + 1 + indent_len
			return true
		}, w})

	keybind.bind_single(&w.insert_kb, {code = keybind.KEY_BACKSPACE}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			if w.buffer == nil do return false

			offset := get_cursor_offset(w)
			if offset <= 0 do return true

			_, rune_len := buffer.decode_prev_rune(w.buffer, offset)
			if rune_len <= 0 do return true

			prev_offset := offset - rune_len

			r, _ := buffer.decode_rune_at(w.buffer, prev_offset)
			is_newline := r == '\n'

			buffer.remove(w.buffer, prev_offset, rune_len)

			if is_newline {
				w.cursor_line -= 1
				if w.cursor_line < 0 {
					w.cursor_line = 0
					w.cursor_col = 0
				} else {
					line_start := buffer.get_line_start(w.buffer, w.cursor_line)
					line_end := buffer.get_line_end(w.buffer, w.cursor_line)
					w.cursor_col = line_end - line_start
				}
			} else {
				w.cursor_col -= rune_len
				if w.cursor_col < 0 {
					w.cursor_col = 0
				}
			}
			w.cursor_off = prev_offset
			return true
		}, w})

	keybind.bind_single(&w.insert_kb, {code = keybind.KEY_DELETE}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			if w.buffer == nil do return false

			offset := get_cursor_offset(w)
			text_len := buffer.len_bytes(w.buffer)
			if offset >= text_len do return true

			r, sz := buffer.decode_rune_at(w.buffer, offset)
			if sz <= 0 do return true

			is_newline := r == '\n'
			buffer.remove(w.buffer, offset, sz)

			if is_newline {
				clamp_cursor(w)
			}
			return true
		}, w})

	keybind.bind_single(&w.insert_kb, {code = keybind.KEY_UP}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_cursor(w, -1, 0)
			return true
		}, w})

	keybind.bind_single(&w.insert_kb, {code = keybind.KEY_DOWN}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_cursor(w, 1, 0)
			return true
		}, w})

	keybind.bind_single(&w.insert_kb, {code = keybind.KEY_LEFT}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_cursor(w, 0, -1)
			return true
		}, w})

	keybind.bind_single(&w.insert_kb, {code = keybind.KEY_RIGHT}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			move_cursor(w, 0, 1)
			return true
		}, w})
}
