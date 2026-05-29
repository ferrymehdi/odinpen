package finder

import "../config"
import "../core/render"
import "core:fmt"
import "core:unicode/utf8"

draw :: proc(r: ^render.renderer_state, ff: ^finder_state, space: render.rect) {
	popup_font_size := 18.0 * config.global_config.ui_scale
	popup_char_size := render.get_cell_size(r, popup_font_size)
	scale := config.global_config.ui_scale

	render.fill_rect(r, space, config.global_config.colorscheme.overlay_bg)

	finder_w := min(space.w - 20 * scale, 1000.0 * scale)
	finder_h := min(space.h - 20 * scale, 750.0 * scale)
	if finder_w < 300.0 * scale do finder_w = min(space.w, 300.0 * scale)
	if finder_h < 200.0 * scale do finder_h = min(space.h, 200.0 * scale)

	finder_x := space.x + (space.w - finder_w) / 2
	finder_y := space.y + (space.h - finder_h) / 2

	finder_rect := render.rect{finder_x, finder_y, finder_w, finder_h}
	render.fill_rect(r, finder_rect, config.global_config.colorscheme.popup_bg)
	render.draw_rect(r, finder_rect, 2.0, config.global_config.colorscheme.popup_border)

	input_box_y := finder_y + 15 * scale
	input_box_h := popup_char_size.y + 12 * scale
	draw_input(
		r,
		ff,
		finder_x + 15 * scale,
		input_box_y,
		finder_w - 30 * scale,
		input_box_h,
		scale,
		popup_font_size,
		popup_char_size,
	)

	list_start_y := input_box_y + input_box_h + 10 * scale
	list_avail_h := finder_y + finder_h - list_start_y - 15 * scale
	draw_list(
		r,
		ff,
		finder_x,
		list_start_y,
		finder_w,
		list_avail_h,
		scale,
		popup_font_size,
		popup_char_size,
	)
}

draw_input :: proc(
	r: ^render.renderer_state,
	ff: ^finder_state,
	x, y, w, h, scale, popup_font_size: f32,
	popup_char_size: [2]f32,
) {
	input_box := render.rect{x, y, w, h}
	render.fill_rect(r, input_box, config.global_config.colorscheme.bg)
	render.draw_rect(r, input_box, 1.0, config.global_config.colorscheme.popup_border)

	input_str := string(ff.input[:])
	render.draw_text(
		r,
		input_str,
		{x + 7 * scale, y + 6 * scale},
		config.global_config.colorscheme.fg,
		popup_font_size,
	)

	rune_count := 0
	for _, index in input_str {
		if index >= ff.cursor do break
		rune_count += 1
	}
	cursor_x := x + 7 * scale + f32(rune_count) * popup_char_size.x
	cursor_rect := render.rect{cursor_x, y + 6 * scale, 2.0, popup_char_size.y}
	render.fill_rect(r, cursor_rect, config.global_config.colorscheme.cursor_solid)
}

draw_list :: proc(
	r: ^render.renderer_state,
	ff: ^finder_state,
	finder_x, y, finder_w, avail_h, scale, popup_font_size: f32,
	popup_char_size: [2]f32,
) {
	list_rows := max(0, int(avail_h / popup_char_size.y))

	scroll_offset := 0
	if ff.selected >= list_rows {
		scroll_offset = ff.selected - list_rows + 1
	}

	for i := 0; i < list_rows; i += 1 {
		idx := scroll_offset + i
		if idx >= len(ff.filtered) do break

		match_item := ff.filtered[idx]
		row_y := y + f32(i) * popup_char_size.y

		if idx == ff.selected {
			sel_rect := render.rect {
				finder_x + 15 * scale,
				row_y,
				finder_w - 30 * scale,
				popup_char_size.y,
			}
			render.fill_rect(r, sel_rect, config.global_config.colorscheme.popup_sel)
		}

		pointer := idx == ff.selected ? "> " : "  "
		color :=
			idx == ff.selected ? config.global_config.colorscheme.popup_text_sel : config.global_config.colorscheme.popup_text

		draw_row(
			r,
			match_item.item,
			pointer,
			color,
			finder_x,
			row_y,
			finder_w,
			scale,
			popup_font_size,
			popup_char_size,
		)
	}
}

draw_row :: proc(
	r: ^render.renderer_state,
	item, pointer: string,
	color: [4]f32,
	finder_x, row_y, finder_w, scale, popup_font_size: f32,
	popup_char_size: [2]f32,
) {
	display_str := fmt.tprintf("%s%s", pointer, item)
	max_chars := int((finder_w - 30 * scale) / popup_char_size.x)

	if max_chars <= 3 {
		if max_chars > 0 {
			render.draw_text(r, "...", {finder_x + 15 * scale, row_y}, color, popup_font_size)
		}
		return
	}

	rune_count := utf8.rune_count_in_string(display_str)
	if rune_count > max_chars {
		runes_to_skip := rune_count - (max_chars - 3)
		byte_offset := 0
		skip_count := 0
		for _, idx in display_str {
			if skip_count == runes_to_skip {
				byte_offset = idx
				break
			}
			skip_count += 1
		}
		truncated_display := fmt.tprintf("...%s", display_str[byte_offset:])
		render.draw_text(
			r,
			truncated_display,
			{finder_x + 15 * scale, row_y},
			color,
			popup_font_size,
		)
		return
	}

	render.draw_text(r, display_str, {finder_x + 15 * scale, row_y}, color, popup_font_size)
}
