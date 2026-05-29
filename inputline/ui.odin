package inputline

import "../config"
import "../core/render"
import "core:strings"
import "core:unicode/utf8"

draw :: proc(r: ^render.renderer_state, space: render.rect) -> render.rect {
	scale := config.global_config.ui_scale
	cmd_height := 22.0 * scale

	cmd_y := space.y + space.h - cmd_height
	cmd_rect := render.rect {
		x = space.x,
		y = cmd_y,
		w = space.w,
		h = cmd_height,
	}

	render.fill_rect(r, cmd_rect, config.global_config.colorscheme.bg)

	ui_font_size := 18.0 * scale
	sl_char_size := render.get_cell_size(r, ui_font_size)

	if global_input_line.is_active {
		cmd_text_y := cmd_rect.y + (cmd_rect.h - sl_char_size.y) / 2
		cmd_start_x := cmd_rect.x + 15.0 * scale


		render.draw_text(
			r,
			global_input_line.message,
			{cmd_start_x, cmd_text_y},
			config.global_config.colorscheme.fg,
			ui_font_size,
		)

		prompt_width := f32(utf8.rune_count_in_string(global_input_line.message)) * sl_char_size.x
		input_x := cmd_start_x + prompt_width


		cmd_input := string(global_input_line.input[:])
		render.draw_text(
			r,
			cmd_input,
			{input_x, cmd_text_y},
			config.global_config.colorscheme.fg,
			ui_font_size,
		)

		cursor_x := input_x + f32(utf8.rune_count_in_string(cmd_input)) * sl_char_size.x
		cursor_width := sl_char_size.x
		cursor_color := config.global_config.colorscheme.cursor
		render.fill_rect(r, {cursor_x, cmd_text_y, cursor_width, sl_char_size.y}, cursor_color)
	} else if len(global_input_line.message) > 0 {
		cmd_text_y := cmd_rect.y + (cmd_rect.h - sl_char_size.y) / 2
		cmd_start_x := cmd_rect.x + 15.0 * scale

		color := config.global_config.colorscheme.fg
		if strings.has_prefix(global_input_line.message, "Error") ||
		   strings.contains(global_input_line.message, "No write") {
			color = {0.85, 0.35, 0.35, 1.0}
		}

		render.draw_text(
			r,
			global_input_line.message,
			{cmd_start_x, cmd_text_y},
			color,
			ui_font_size,
		)
	}

	return render.rect{x = space.x, y = space.y, w = space.w, h = space.h - cmd_height}
}
