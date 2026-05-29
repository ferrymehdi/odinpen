package window

import buf_pkg "../buffer"
import "../config"
import "core:unicode/utf8"

get_line_indent :: proc(line: string) -> int {
	indent_len := 0
	for i := 0; i < len(line); i += 1 {
		if line[i] == ' ' || line[i] == '\t' {
			indent_len += 1
		} else {
			break
		}
	}
	return indent_len
}

visual_line :: struct {
	buffer_line: int,
	segment_idx: int,
	start_col:   int,
	char_count:  int,
}

get_visual_lines :: proc(w: ^window, cols: int) -> [dynamic]visual_line {
	v_lines := make([dynamic]visual_line, 0, 1024, context.temp_allocator)
	if w.buffer == nil do return v_lines

	lc := buf_pkg.line_count(w.buffer)
	for line_idx := 0; line_idx < lc; line_idx += 1 {
		line := buf_pkg.get_line(w.buffer, line_idx)

		if len(line) == 0 {
			append(&v_lines, visual_line{line_idx, 0, 0, 0})
			continue
		}

		col := 0
		start_col := 0
		segment_idx := 0

		for i := 0; i < len(line); i += 1 {
			ch := line[i]
			char_len := 1
			if ch == '\t' {
				char_len = config.global_config.tab_size
			}

			if col - start_col + char_len > cols && col > start_col {
				append(&v_lines, visual_line{line_idx, segment_idx, start_col, col - start_col})
				start_col = col
				segment_idx += 1
			}
			col += char_len
		}

		append(&v_lines, visual_line{line_idx, segment_idx, start_col, col - start_col})
	}

	return v_lines
}

get_cursor_visual_line_idx :: proc(win: ^window, v_lines: []visual_line) -> int {
	cursor_vc := get_visual_column(win)
	for vl, idx in v_lines {
		if vl.buffer_line == win.cursor_line {
			is_last_segment :=
				idx == len(v_lines) - 1 || v_lines[idx + 1].buffer_line != win.cursor_line
			if is_last_segment ||
			   (cursor_vc >= vl.start_col && cursor_vc < vl.start_col + vl.char_count) {
				return idx
			}
		}
	}
	return 0
}

get_byte_col_from_visual_col :: proc(line: string, target_vc: int) -> int {
	visual_col := 0
	byte_idx := 0
	for r in line {
		if visual_col >= target_vc do break
		sz := utf8.rune_size(r)
		if r == '\t' {
			visual_col += config.global_config.tab_size
		} else {
			visual_col += 1
		}
		byte_idx += sz
	}
	return byte_idx
}
