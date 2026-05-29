package window

import "../buffer"
import "../config"
import "../core/render"
import "../explorer"
import "../finder"
import "core:fmt"

draw :: proc(r: ^render.renderer_state, win: ^window, space: render.rect) -> render.rect {
	remaining_space := draw_status(r, space, win)

	if win.explorer != nil {
		explorer.draw(r, win.explorer, remaining_space)
		return space
	}

	if win.finder != nil {
		finder.draw(r, win.finder, remaining_space)
		return space
	}

	draw_editor_content(r, win, remaining_space)
	return space
}

draw_editor_content :: proc(r: ^render.renderer_state, win: ^window, space: render.rect) {
	margin: f32 = 2.0
	char_size := render.get_cell_size(r, win.font_size)

	max_val := buffer.line_count(win.buffer)
	width := 1
	temp := max_val
	for temp >= 10 {
		width += 1
		temp /= 10
	}
	gutter_width := char_size.x * f32(width)

	render.fill_rect(r, space, config.global_config.colorscheme.bg)

	gutter_rect := render.rect{space.x, space.y, gutter_width, space.h}
	render.fill_rect(r, gutter_rect, config.global_config.colorscheme.bar_bg)
	render.draw_rect(r, gutter_rect, 1.0, config.global_config.colorscheme.bar_border)

	text_area := render.rect {
		x = space.x + gutter_width + margin,
		y = space.y + margin,
		w = space.w - gutter_width - margin * 2,
		h = space.h - margin * 2,
	}

	rows := max(0, int(text_area.h / char_size.y))
	cols := max(0, int(text_area.w / char_size.x))

	win.width_in_chars = cols

	v_lines := get_visual_lines(win, cols)

	update_viewport_scroll(win, rows, cols, v_lines[:])

	line_start := int(win.scroll_y)
	cursor_vl_idx := get_cursor_visual_line_idx(win, v_lines[:])

	for i := 0; i < rows; i += 1 {
		v_idx := line_start + i
		if v_idx >= len(v_lines) {
			break
		}

		vl := v_lines[v_idx]
		y := text_area.y + f32(i) * char_size.y

		draw_line_number(r, win, gutter_rect.x, y, vl.buffer_line, width, vl.segment_idx == 0)
		draw_line_text(
			r,
			win,
			text_area.x,
			y,
			vl.buffer_line,
			vl.start_col,
			vl.char_count,
			char_size,
			v_idx == cursor_vl_idx,
		)
	}
}

update_viewport_scroll :: proc(win: ^window, rows, cols: int, v_lines: []visual_line) {
	scrolloff := min(5, rows / 2)
	cursor_vl_idx := get_cursor_visual_line_idx(win, v_lines)

	if cursor_vl_idx < int(win.scroll_y) + scrolloff {
		win.scroll_y = f32(cursor_vl_idx - scrolloff)
	} else if cursor_vl_idx >= int(win.scroll_y) + rows - scrolloff {
		win.scroll_y = f32(cursor_vl_idx - rows + 1 + scrolloff)
	}

	max_scroll := max(0, len(v_lines) - rows)
	if win.scroll_y > f32(max_scroll) do win.scroll_y = f32(max_scroll)
	if win.scroll_y < 0 do win.scroll_y = 0

	win.scroll_x = 0
}

draw_line_number :: proc(
	r: ^render.renderer_state,
	win: ^window,
	x, y: f32,
	line_idx, gutter_char_width: int,
	should_draw: bool,
) {
	if !should_draw do return
	num := line_idx == win.cursor_line ? (line_idx + 1) : abs(line_idx - win.cursor_line)
	fmt_str := fmt.tprintf("%% %dd", gutter_char_width)
	line_num_str := fmt.tprintf(fmt_str, num)
	color :=
		line_idx == win.cursor_line ? config.global_config.colorscheme.gutter_fg : config.global_config.colorscheme.gutter_rel
	render.draw_text(r, line_num_str, {x, y}, color, win.font_size)
}

draw_line_text :: proc(
	r: ^render.renderer_state,
	win: ^window,
	start_x, y: f32,
	line_idx, start_col, char_count: int,
	char_size: [2]f32,
	is_cursor_line: bool,
) {
	line := buffer.get_line(win.buffer, line_idx)

	visible_text := slice_line_text(line, start_col, char_count)

	render.draw_text(
		r,
		visible_text,
		{start_x, y},
		config.global_config.colorscheme.fg,
		win.font_size,
	)
	if is_cursor_line {
		draw_text_cursor(r, win, start_x, y, start_col, char_size)
	}
}

slice_line_text :: proc(line: string, start_col, max_cols: int) -> string {
	if len(line) == 0 do return ""

	builder := make([dynamic]u8, context.temp_allocator)
	col := 0

	for i := 0; i < len(line); i += 1 {
		ch := line[i]
		char_len := 1
		if ch == '\t' {
			char_len = config.global_config.tab_size
		}

		if col >= start_col + max_cols {
			break
		}

		if col + char_len <= start_col {
			col += char_len
			continue
		}

		if ch == '\t' {
			tab_start := col
			tab_end := col + char_len
			visible_start := max(tab_start, start_col)
			visible_end := min(tab_end, start_col + max_cols)
			visible_len := visible_end - visible_start
			for j := 0; j < visible_len; j += 1 {
				append(&builder, ' ')
			}
		} else {
			append(&builder, ch)
		}
		col += char_len
	}

	return string(builder[:])
}

draw_text_cursor :: proc(
	r: ^render.renderer_state,
	win: ^window,
	start_x, y: f32,
	start_col: int,
	char_size: [2]f32,
) {
	if is_active(win) {
		visual_col := get_visual_column(win)
		cursor_col_visible := visual_col - start_col
		cursor_x := start_x + f32(cursor_col_visible) * char_size.x
		cursor_width: f32 = 2.0
		cursor_color := config.global_config.colorscheme.cursor_solid
		if win.mode == .Normal || win.mode == .Visual {
			cursor_width = char_size.x
			cursor_color = config.global_config.colorscheme.cursor
		}
		render.fill_rect(r, {cursor_x, y, cursor_width, char_size.y}, cursor_color)
	}
}

draw_status :: proc(r: ^render.renderer_state, space: render.rect, win: ^window) -> render.rect {
	scale := config.global_config.ui_scale
	sl_height := 22.0 * scale

	sl_rect := render.rect {
		x = space.x,
		y = space.y + space.h - sl_height,
		w = space.w,
		h = sl_height,
	}

	draw_status_bg(r, sl_rect, is_active(win))

	ui_font_size := 18.0 * scale
	sl_char_size := render.get_cell_size(r, ui_font_size)
	text_y := sl_rect.y + (sl_rect.h - sl_char_size.y) / 2

	start_x := sl_rect.x + 10.0 * scale

	mode_len_chars := draw_status_mode(r, start_x, text_y, win, ui_font_size)
	draw_status_file_path(
		r,
		start_x,
		text_y,
		win,
		scale,
		ui_font_size,
		mode_len_chars,
		sl_char_size.x,
	)
	draw_status_position(r, sl_rect, text_y, win, scale, ui_font_size, sl_char_size.x)

	return render.rect{x = space.x, y = space.y, w = space.w, h = space.h - sl_height}
}

draw_status_bg :: proc(r: ^render.renderer_state, rect: render.rect, active: bool) {
	bg_color :=
		active ? config.global_config.colorscheme.bar_bg : config.global_config.colorscheme.bg
	render.fill_rect(r, rect, bg_color)
	render.fill_rect(r, {rect.x, rect.y, rect.w, 1.0}, config.global_config.colorscheme.bar_border)
}

draw_status_mode :: proc(
	r: ^render.renderer_state,
	x, y: f32,
	win: ^window,
	ui_font_size: f32,
) -> int {
	mode_color := config.global_config.colorscheme.bar_text
	if is_active(win) {
		switch win.mode {
		case .Normal:
			mode_color = config.global_config.colorscheme.mode_normal
		case .Insert:
			mode_color = config.global_config.colorscheme.mode_insert
		case .Visual:
			mode_color = config.global_config.colorscheme.mode_visual
		}
	}
	mode_str := fmt.tprintf("[%v]", win.mode)
	render.draw_text(r, mode_str, {x, y}, mode_color, ui_font_size)
	return len(mode_str)
}

draw_status_file_path :: proc(
	r: ^render.renderer_state,
	start_x, y: f32,
	win: ^window,
	scale, ui_font_size: f32,
	mode_len_chars: int,
	char_size_x: f32,
) {
	path_x := start_x + f32(mode_len_chars) * char_size_x + 15.0 * scale
	path_str := "[No Name]"
	if win.buffer != nil && len(win.buffer.path) > 0 {
		path_str = win.buffer.path
	}
	path_color :=
		is_active(win) ? config.global_config.colorscheme.bar_active_text : config.global_config.colorscheme.bar_text
	render.draw_text(r, path_str, {path_x, y}, path_color, ui_font_size)
}

draw_status_position :: proc(
	r: ^render.renderer_state,
	sl_rect: render.rect,
	y: f32,
	win: ^window,
	scale, ui_font_size, char_size_x: f32,
) {
	file_type_str := "Plain Text"
	if win.buffer != nil && len(win.buffer.file_type) > 0 {
		file_type_str = win.buffer.file_type
	}

	pos_str := fmt.tprintf("%d:%d", win.cursor_line + 1, get_visual_column(win) + 1)
	right_str := fmt.tprintf("%s | %s", file_type_str, pos_str)
	right_align := sl_rect.x + sl_rect.w - f32(len(right_str)) * char_size_x - 10.0 * scale

	render.draw_text(
		r,
		right_str,
		{right_align, y},
		config.global_config.colorscheme.bar_text,
		ui_font_size,
	)
}
