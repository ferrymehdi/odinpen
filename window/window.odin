package window

import buf_pkg "../buffer"
import "../config"
import "../core/command"
import "../core/keybind"
import "../explorer"
import "../finder"
import "core:os"
import "core:path/filepath"
import "core:unicode/utf8"

mode :: enum {
	Normal,
	Insert,
	Visual,
}

window_flag :: enum {
	Is_Active,
}

window_flags :: bit_set[window_flag]

window :: struct {
	id:             window_id,
	buffer:         ^buf_pkg.buffer,
	cursor_line:    int,
	cursor_col:     int,
	cursor_off:     int,
	scroll_x:       f32,
	scroll_y:       f32,
	position:       [2]f32,
	size:           [2]f32,
	flags:          window_flags,
	normal_kb:      keybind.key_binder,
	insert_kb:      keybind.key_binder,
	visual_kb:      keybind.key_binder,
	cmd_binder:     command.command_binder,
	mode:           mode,
	font_size:      f32,
	explorer:       ^explorer.file_explorer,
	finder:         ^finder.finder_state,
	buffers:        ^[dynamic]^buf_pkg.buffer,
	width_in_chars: int,
}

window_id :: distinct int

init_win :: proc(
	id: window_id,
	buf: ^buf_pkg.buffer,
	buffers: ^[dynamic]^buf_pkg.buffer,
) -> ^window {
	w := new(window)
	init_win_ptr(w, id, buf, buffers)
	return w
}

init_win_ptr :: proc(
	w: ^window,
	id: window_id,
	buf: ^buf_pkg.buffer,
	buffers: ^[dynamic]^buf_pkg.buffer,
) {
	assert(buf != nil)
	w.id = id
	w.buffer = buf
	w.cursor_line = 0
	w.cursor_col = 0
	w.cursor_off = 0
	w.scroll_x = 0
	w.scroll_y = 0
	w.position = {0, 0}
	w.size = {80, 24}
	w.flags = {.Is_Active}
	w.font_size = 18.0
	w.explorer = nil
	w.finder = nil
	w.buffers = buffers
	w.width_in_chars = 80

	keybind.init(&w.normal_kb)
	keybind.init(&w.insert_kb)
	keybind.init(&w.visual_kb)
	command.init(&w.cmd_binder)
	w.mode = .Normal
	setup_normal_keybinds(w)
	setup_insert_keybinds(w)
	setup_visual_keybinds(w)
	setup_commands(w)
}

init :: proc {
	init_win,
	init_win_ptr,
}

clone :: proc(w: ^window, new_id: window_id) -> ^window {
	new_win := init_win(new_id, w.buffer, w.buffers)
	new_win.cursor_line = w.cursor_line
	new_win.cursor_col = w.cursor_col
	new_win.cursor_off = w.cursor_off
	new_win.scroll_x = w.scroll_x
	new_win.scroll_y = w.scroll_y
	new_win.mode = w.mode
	new_win.font_size = w.font_size
	return new_win
}

destroy :: proc(w: ^window) {
	w.buffer = nil
	if w.explorer != nil {
		explorer.destroy(w.explorer)
		free(w.explorer)
		w.explorer = nil
	}
	if w.finder != nil {
		finder.destroy(w.finder)
		free(w.finder)
		w.finder = nil
	}
	keybind.destroy(&w.normal_kb)
	keybind.destroy(&w.insert_kb)
	keybind.destroy(&w.visual_kb)
	command.destroy(&w.cmd_binder)
}

get_mode :: proc(w: ^window) -> mode {
	return w.mode
}

set_mode :: proc(w: ^window, mode: mode) {
	w.mode = mode
}

handle_command :: proc(w: ^window, name: string, args: []string) -> bool {
	return command.execute(&w.cmd_binder, name, args)
}

preview_handle_key :: proc(w: ^window, key: keybind.key) -> bool {
	if .Control in key.mods && (key.code == '=' || key.code == '-') {
		new_size := w.font_size
		if key.code == '=' {
			new_size += 2.0
			if new_size > 256.0 do new_size = 256.0
		} else {
			new_size -= 2.0
			if new_size < 4.0 do new_size = 4.0
		}
		w.font_size = new_size
		return true
	}

	if w.explorer != nil {
		return handle_explorer_key(w, key)
	}
	if w.finder != nil {
		return handle_finder_key(w, key)
	}

	return false
}

handle_key :: proc(w: ^window, key: keybind.key) -> bool {
	kb: ^keybind.key_binder = nil
	switch w.mode {
	case .Normal:
		kb = &w.normal_kb
	case .Insert:
		kb = &w.insert_kb
	case .Visual:
		kb = &w.visual_kb
	}

	if kb != nil && keybind.handle(kb, key) {
		return true
	}

	if w.mode == .Insert && key.char != 0 {
		handle_char(w, key.char)
		return true
	}

	return false
}

get_id :: proc(w: ^window) -> window_id {
	return w.id
}

get_buffer :: proc(w: ^window) -> ^buf_pkg.buffer {
	return w.buffer
}

set_buffer :: proc(w: ^window, buf: ^buf_pkg.buffer) {
	assert(buf != nil)
	w.buffer = buf
	w.cursor_line = 0
	w.cursor_col = 0
	w.cursor_off = 0
	clamp_cursor(w)
}

get_cursor_line :: proc(w: ^window) -> int {
	return w.cursor_line
}

set_cursor_line :: proc(w: ^window, line: int) {
	w.cursor_line = line
	if w.buffer != nil && line >= 0 {
		lc := buf_pkg.line_count(w.buffer)
		if line >= lc {
			w.cursor_line = lc - 1
		}
		if w.cursor_line < 0 {
			w.cursor_line = 0
		}
	}
}

get_cursor_col :: proc(w: ^window) -> int {
	return w.cursor_col
}

set_cursor_col :: proc(w: ^window, col: int) {
	w.cursor_col = col
}

get_cursor_offset :: proc(w: ^window) -> int {
	if w.buffer == nil {
		return 0
	}
	line := w.cursor_line
	col := w.cursor_col
	return buf_pkg.offset_at_position(w.buffer, line, col)
}

get_scroll_x :: proc(w: ^window) -> f32 {
	return w.scroll_x
}

get_scroll_y :: proc(w: ^window) -> f32 {
	return w.scroll_y
}

set_scroll :: proc(w: ^window, x, y: f32) {
	w.scroll_x = x
	w.scroll_y = y
}

scroll :: proc(w: ^window, dx, dy: f32) {
	w.scroll_x += dx
	w.scroll_y += dy
	if w.scroll_x < 0 {
		w.scroll_x = 0
	}
	if w.scroll_y < 0 {
		w.scroll_y = 0
	}
}

is_active :: proc(w: ^window) -> bool {
	return .Is_Active in w.flags
}

set_active :: proc(w: ^window, active: bool) {
	if active {
		w.flags += {.Is_Active}
	} else {
		w.flags -= {.Is_Active}
	}
}

get_position :: proc(w: ^window) -> [2]f32 {
	return w.position
}

set_position :: proc(w: ^window, pos: [2]f32) {
	w.position = pos
}

get_size :: proc(w: ^window) -> [2]f32 {
	return w.size
}

set_size :: proc(w: ^window, sz: [2]f32) {
	w.size = sz
}

get_font_size :: proc(w: ^window) -> f32 {
	return w.font_size
}

set_font_size :: proc(w: ^window, size: f32) {
	w.font_size = size
}

move_cursor :: proc(w: ^window, delta_line, delta_col: int) {
	if w.buffer == nil {
		return
	}

	w.cursor_line += delta_line
	if delta_col != 0 {
		w.cursor_col += delta_col
	}

	clamp_cursor(w)
}

clamp_cursor :: proc(w: ^window) {
	if w.buffer == nil {
		w.cursor_line = 0
		w.cursor_col = 0
		w.cursor_off = 0
		return
	}

	lc := buf_pkg.line_count(w.buffer)
	if w.cursor_line < 0 {
		w.cursor_line = 0
	}
	if w.cursor_line >= lc {
		w.cursor_line = lc - 1
	}
	if w.cursor_line < 0 {
		w.cursor_line = 0
	}

	line_start := buf_pkg.get_line_start(w.buffer, w.cursor_line)
	line_end := buf_pkg.get_line_end(w.buffer, w.cursor_line)
	max_col := line_end - line_start

	max_col_allowed := max_col
	if w.mode == .Normal || w.mode == .Visual {
		max_col_allowed = max(0, max_col - 1)
	}

	if w.cursor_col < 0 {
		w.cursor_col = 0
	}
	if w.cursor_col > max_col_allowed {
		w.cursor_col = max_col_allowed
	}

	w.cursor_off = line_start + w.cursor_col
}

set_cursor_from_offset :: proc(w: ^window, offset: int) {
	if w.buffer == nil do return
	b := w.buffer

	line_idx := buf_pkg.find_line_index(b, offset)
	line_start := buf_pkg.get_line_start(b, line_idx)

	w.cursor_line = line_idx
	w.cursor_col = offset - line_start
	clamp_cursor(w)
}

move_to_next_word :: proc(w: ^window, big_word: bool = false) {
	if w.buffer == nil do return
	next_off := buf_pkg.get_next_word_offset(w.buffer, w.cursor_off, big_word)
	total_len := buf_pkg.len_bytes(w.buffer)
	if next_off >= total_len {
		next_off = total_len - 1
		if next_off < 0 do next_off = 0
	}
	set_cursor_from_offset(w, next_off)
}

move_to_prev_word :: proc(w: ^window, big_word: bool = false) {
	if w.buffer == nil do return
	prev_off := buf_pkg.get_prev_word_offset(w.buffer, w.cursor_off, big_word)
	set_cursor_from_offset(w, prev_off)
}

move_to_end_of_word :: proc(w: ^window, big_word: bool = false) {
	if w.buffer == nil do return
	idx := buf_pkg.get_end_of_word_offset(w.buffer, w.cursor_off, big_word)
	total_len := buf_pkg.len_bytes(w.buffer)
	if idx >= total_len {
		idx = total_len - 1
		if idx < 0 do idx = 0
	}
	set_cursor_from_offset(w, idx)
}

delete_char_under_cursor :: proc(w: ^window) {
	if w.buffer == nil do return

	clamp_cursor(w)

	text_len := buf_pkg.len_bytes(w.buffer)
	if text_len == 0 do return

	idx := w.cursor_off
	if idx >= text_len do return

	r, sz := buf_pkg.decode_rune_at(w.buffer, idx)
	if sz <= 0 || r == '\n' do return

	buf_pkg.remove(w.buffer, idx, sz)

	clamp_cursor(w)
}

move_to_end_of_line :: proc(w: ^window) {
	if w.buffer == nil do return
	line_end := buf_pkg.get_line_end(w.buffer, w.cursor_line)
	line_start := buf_pkg.get_line_start(w.buffer, w.cursor_line)
	w.cursor_col = line_end - line_start
	clamp_cursor(w)
}

move_to_start_of_line :: proc(w: ^window) {
	if w.buffer == nil do return
	w.cursor_col = 0
	clamp_cursor(w)
}

move_to_first_non_blank :: proc(w: ^window) {
	if w.buffer == nil do return
	line := buf_pkg.get_line(w.buffer, w.cursor_line)

	col := 0
	for col < len(line) {
		r, sz := utf8.decode_rune_in_string(line[col:])
		if sz == 0 do break
		if r != ' ' && r != '\t' {
			break
		}
		col += sz
	}

	w.cursor_col = col
	w.cursor_off = buf_pkg.get_line_start(w.buffer, w.cursor_line) + col
	clamp_cursor(w)
}

move_to_last_line :: proc(w: ^window) {
	if w.buffer == nil do return
	lc := buf_pkg.line_count(w.buffer)
	if lc > 0 {
		set_cursor_from_offset(w, buf_pkg.get_line_start(w.buffer, lc - 1))
	}
}

contains_point :: proc(w: ^window, x, y: f32) -> bool {
	return(
		x >= w.position.x &&
		x < w.position.x + w.size.x &&
		y >= w.position.y &&
		y < w.position.y + w.size.y \
	)
}

handle_char :: proc(w: ^window, codepoint: rune) {
	if w.mode != .Insert || w.buffer == nil do return

	buf, n := utf8.encode_rune(codepoint)
	char_str := string(buf[:n])

	offset := get_cursor_offset(w)
	buf_pkg.insert(w.buffer, offset, char_str)

	w.cursor_col += n
	clamp_cursor(w)
}

open_file :: proc(w: ^window, path: string) -> bool {
	if len(path) == 0 do return false

	buf: ^buf_pkg.buffer = nil
	for b in w.buffers {
		if b.path == path {
			buf = b
			break
		}
	}

	if buf == nil {
		buf = new(buf_pkg.buffer)
		buf_pkg.init(buf)
		if buf_pkg.load_from_file(buf, path) {
			append(w.buffers, buf)
		} else {
			buf_pkg.destroy(buf)
			free(buf)
			return false
		}
	}

	set_buffer(w, buf)
	return true
}

toggle_explorer :: proc(w: ^window) {
	if w.explorer != nil {
		explorer.destroy(w.explorer)
		free(w.explorer)
		w.explorer = nil
	} else {
		w.explorer = new(explorer.file_explorer)
		explorer.init(w.explorer, ".", {explorer_on_open_file, w})
	}
}

toggle_finder :: proc(w: ^window, path: string) {
	if w.finder != nil {
		finder.destroy(w.finder)
		free(w.finder)
		w.finder = nil
	} else {
		w.finder = new(finder.finder_state)
		files := make([dynamic]string, context.temp_allocator)
		collect_files_recursive(path, &files)

		finder.init(w.finder, files[:], {finder_on_select_file, w})
	}
}

explorer_on_open_file :: proc(env: rawptr, path: string) -> bool {
	w := (^window)(env)
	return open_file(w, path)
}

finder_on_select_file :: proc(env: rawptr, filepath: string) -> bool {
	w := (^window)(env)
	return open_file(w, filepath)
}

collect_files_recursive :: proc(dir: string, files_list: ^[dynamic]string) {
	context.allocator = context.temp_allocator

	f, err := os.open(dir)
	if err != 0 do return
	defer os.close(f)

	infos, err2 := os.read_dir(f, -1, context.temp_allocator)
	if err2 != 0 do return
	defer os.file_info_slice_delete(infos, context.temp_allocator)

	for info in infos {
		if info.name == "." || info.name == ".." do continue

		should_ignore := false
		for ignore_dir in config.global_config.ignored_directories {
			if info.name == ignore_dir {
				should_ignore = true
				break
			}
		}
		if should_ignore do continue

		path, join_err := filepath.join({dir, info.name})
		if join_err != nil do continue

		if info.type == .Directory {
			collect_files_recursive(path, files_list)
		} else {
			append(files_list, path)
		}
	}
}

handle_explorer_key :: proc(w: ^window, key: keybind.key) -> bool {
	fe := w.explorer
	if fe == nil do return false

	if key.code == keybind.KEY_ESCAPE || key.code == 'q' {
		if fe.modal.type != .None {
			explorer.close_modal(fe)
			return true
		}
		explorer.destroy(fe)
		free(fe)
		w.explorer = nil
		return true
	}

	if fe.modal.type != .None {
		ret := explorer.handle_modal_key(fe, key)
		if fe.should_close {
			explorer.destroy(fe)
			free(fe)
			w.explorer = nil
		}
		return ret
	}

	ret := keybind.handle(&fe.key_binder, key)
	if fe.should_close {
		explorer.destroy(fe)
		free(fe)
		w.explorer = nil
	}
	return ret
}

handle_finder_key :: proc(w: ^window, key: keybind.key) -> bool {
	ff := w.finder
	if ff == nil do return false

	ret := finder.handle_key(ff, key)
	if ff.should_close {
		finder.destroy(ff)
		free(ff)
		w.finder = nil
	}
	return ret
}

get_visual_column :: proc(w: ^window) -> int {
	if w.buffer == nil do return 0
	line := buf_pkg.get_line(w.buffer, w.cursor_line)
	visual_col := 0
	byte_idx := 0
	for r in line {
		if byte_idx >= w.cursor_col do break
		sz := utf8.rune_size(r)
		if r == '\t' {
			visual_col += config.global_config.tab_size
		} else {
			visual_col += 1
		}
		byte_idx += sz
	}
	return visual_col
}

move_to_first_line :: proc(w: ^window) {
	if w.buffer == nil do return
	w.cursor_line = 0
	w.cursor_col = 0
	w.cursor_off = 0
	clamp_cursor(w)
}

open_line_below :: proc(w: ^window) {
	if w.buffer == nil do return
	line_end := buf_pkg.get_line_end(w.buffer, w.cursor_line)

	line := buf_pkg.get_line(w.buffer, w.cursor_line)
	indent_len := get_line_indent(line)

	buf_pkg.insert(w.buffer, line_end, "\n")
	if indent_len > 0 {
		buf_pkg.insert(w.buffer, line_end + 1, line[:indent_len])
	}
	w.cursor_line += 1
	w.cursor_col = indent_len
	w.cursor_off = line_end + 1 + indent_len
	w.mode = .Insert
}

open_line_above :: proc(w: ^window) {
	if w.buffer == nil do return
	line_start := buf_pkg.get_line_start(w.buffer, w.cursor_line)

	line := buf_pkg.get_line(w.buffer, w.cursor_line)
	indent_len := get_line_indent(line)

	buf_pkg.insert(w.buffer, line_start, "\n")
	if indent_len > 0 {
		buf_pkg.insert(w.buffer, line_start, line[:indent_len])
	}
	w.cursor_col = indent_len
	w.cursor_off = line_start + indent_len
	w.mode = .Insert
}

delete_line :: proc(w: ^window) {
	if w.buffer == nil do return
	lc := buf_pkg.line_count(w.buffer)
	if lc == 0 do return

	line_start := buf_pkg.get_line_start(w.buffer, w.cursor_line)
	line_end: int

	if w.cursor_line + 1 < lc {
		line_end = buf_pkg.get_line_start(w.buffer, w.cursor_line + 1)
	} else {
		line_end = buf_pkg.len_bytes(w.buffer)
		if line_start > 0 {
			line_start -= 1
		}
	}

	length := line_end - line_start
	if length > 0 {
		buf_pkg.remove(w.buffer, line_start, length)
	}

	clamp_cursor(w)
}

delete_word :: proc(w: ^window) {
	if w.buffer == nil do return

	start := get_cursor_offset(w)
	end := buf_pkg.get_next_word_offset(w.buffer, start, false)

	start_line := buf_pkg.find_line_index(w.buffer, start)
	end_line := buf_pkg.find_line_index(w.buffer, end)

	if end_line > start_line {
		end = buf_pkg.get_line_end(w.buffer, start_line)
	}

	if end > start {
		buf_pkg.remove(w.buffer, start, end - start)
		set_cursor_from_offset(w, start)
	}
}

delete_to_end_of_line :: proc(w: ^window) {
	if w.buffer == nil do return
	offset := get_cursor_offset(w)
	line_end := buf_pkg.get_line_end(w.buffer, w.cursor_line)
	length := line_end - offset
	if length > 0 {
		buf_pkg.remove(w.buffer, offset, length)
	}
	clamp_cursor(w)
}

join_lines :: proc(w: ^window) {
	if w.buffer == nil do return
	lc := buf_pkg.line_count(w.buffer)
	if w.cursor_line + 1 >= lc do return

	line_end := buf_pkg.get_line_end(w.buffer, w.cursor_line)
	next_line_start := buf_pkg.get_line_start(w.buffer, w.cursor_line + 1)

	next_line := buf_pkg.get_line(w.buffer, w.cursor_line + 1)
	skip := get_line_indent(next_line)

	remove_start := line_end
	remove_len := (next_line_start + skip) - line_end
	if remove_len > 0 {
		buf_pkg.remove(w.buffer, remove_start, remove_len)

		buf_pkg.insert(w.buffer, remove_start, " ")
	}

	w.cursor_col = line_end - buf_pkg.get_line_start(w.buffer, w.cursor_line)
	clamp_cursor(w)
}
