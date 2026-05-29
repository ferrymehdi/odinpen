package session

import "../config"
import "../core/render"
import "../tab"
import "core:unicode/utf8"

draw :: proc(r: ^render.renderer_state, s: ^session, space: render.rect) -> render.rect {
	scale := config.global_config.ui_scale
	tb_height: f32 = 22.0 * scale

	tb_rect := render.rect {
		x = space.x,
		y = space.y,
		w = space.w,
		h = tb_height,
	}

	draw_tab_bar_background(r, tb_rect)
	draw_tabs(r, s, tb_rect, scale)

	remaining_space := render.rect {
		x = space.x,
		y = space.y + tb_height,
		w = space.w,
		h = space.h - tb_height,
	}

	active_tab := focused_tab(s)
	if active_tab != nil {
		tab.draw(r, active_tab, remaining_space)
	}

	return remaining_space
}

draw_tab_bar_background :: proc(r: ^render.renderer_state, rect: render.rect) {
	render.fill_rect(r, rect, config.global_config.colorscheme.bar_bg)

	render.fill_rect(
		r,
		{rect.x, rect.y + rect.h - 1.0, rect.w, 1.0},
		config.global_config.colorscheme.bar_border,
	)
}

draw_tabs :: proc(r: ^render.renderer_state, s: ^session, tb_rect: render.rect, scale: f32) {
	start_x := tb_rect.x + 15.0 * scale
	ui_font_size := 18.0 * scale
	sl_char_size := render.get_cell_size(r, ui_font_size)
	text_y := tb_rect.y + (tb_rect.h - sl_char_size.y) / 2

	tab_x := start_x
	for t, i in s.tabs {
		tab_width := f32(utf8.rune_count_in_string(t.name)) * sl_char_size.x
		color := config.global_config.colorscheme.bar_text

		if i == s.active_tab {
			color = config.global_config.colorscheme.bar_active_text

			render.fill_rect(
				r,
				{tab_x - 8 * scale, tb_rect.y, tab_width + 16 * scale, tb_rect.h - 1.0},
				config.global_config.colorscheme.bg,
			)

			render.fill_rect(
				r,
				{tab_x - 8 * scale, tb_rect.y, tab_width + 16 * scale, 2.0 * scale},
				config.global_config.colorscheme.bar_active_line,
			)
		}

		render.draw_text(r, t.name, {tab_x, text_y}, color, ui_font_size)
		tab_x += tab_width + 24.0 * scale
	}
}
