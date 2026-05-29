package explorer

import "../config"
import "../core/render"
import "core:fmt"
import "core:path/filepath"

draw :: proc(r: ^render.renderer_state, fe: ^file_explorer, space: render.rect) {
	scale := config.global_config.ui_scale
	ui_font_size := 18.0 * scale
	char_size := render.get_cell_size(r, ui_font_size)
	margin: f32 = 2.0 * scale

	render.fill_rect(r, space, config.global_config.colorscheme.bg)

	header_height := char_size.y + margin * 2
	draw_header(r, fe, space.x, space.y, space.w, header_height, margin, ui_font_size)

	list_y := space.y + header_height + margin
	list_h := space.h - header_height - margin * 2
	draw_list(r, fe, space.x, list_y, space.w, list_h, char_size, ui_font_size)

	if fe.modal.type != .None {
		draw_modal(r, fe, space, scale)
	}
}

draw_header :: proc(
	r: ^render.renderer_state,
	fe: ^file_explorer,
	x, y, w, h, margin, ui_font_size: f32,
) {
	header_rect := render.rect{x, y, w, h}
	render.fill_rect(r, header_rect, config.global_config.colorscheme.bar_bg)
	render.draw_rect(r, header_rect, 1.0, config.global_config.colorscheme.bar_border)

	header_text: string
	if len(fe.key_binder.sequence) > 0 {
		k := fe.key_binder.sequence[0]
		ch := k.char != 0 ? k.char : rune(k.code)
		header_text = fmt.tprintf("  %s  [Pending: %r]", fe.current_dir, ch)
	} else {
		header_text = fmt.tprintf("  %s", fe.current_dir)
	}
	render.draw_text(
		r,
		header_text,
		{x, y + margin},
		config.global_config.colorscheme.bar_active_text,
		ui_font_size,
	)
}

draw_list :: proc(
	r: ^render.renderer_state,
	fe: ^file_explorer,
	x, y, w, h: f32,
	char_size: [2]f32,
	ui_font_size: f32,
) {
	rows := max(0, int(h / char_size.y))

	scroll_offset := 0
	if fe.selected >= rows {
		scroll_offset = fe.selected - rows + 1
	}

	for i := 0; i < rows; i += 1 {
		entry_idx := scroll_offset + i
		if entry_idx >= len(fe.entries) do break

		entry := fe.entries[entry_idx]
		row_y := y + f32(i) * char_size.y

		if entry_idx == fe.selected {
			sel_rect := render.rect{x, row_y, w, char_size.y}
			render.fill_rect(r, sel_rect, config.global_config.colorscheme.popup_sel)
		}

		pointer := "  "
		if entry_idx == fe.selected {
			pointer = "> "
		}

		is_selected := false
		if entry.name != ".." {
			entry_path, err := filepath.join({fe.current_dir, entry.name})
			if err == nil {
				if entry_path in fe.selections {
					is_selected = fe.selections[entry_path]
				}
				delete(entry_path)
			}
		}

		sel_indicator := "    "
		if entry.name != ".." {
			sel_indicator = is_selected ? "[x] " : "[ ] "
		}

		color := config.global_config.colorscheme.fg
		name_suffix := ""

		if entry.is_dir {
			color = config.global_config.colorscheme.syntax_keyword
			name_suffix = "/"
		} else if entry.is_exec {
			color = config.global_config.colorscheme.syntax_number
			name_suffix = "*"
		}

		display_str := fmt.tprintf("%s%s%s%s", pointer, sel_indicator, entry.name, name_suffix)
		render.draw_text(r, display_str, {x, row_y}, color, ui_font_size)
	}
}

draw_modal :: proc(r: ^render.renderer_state, fe: ^file_explorer, space: render.rect, scale: f32) {
	render.fill_rect(r, space, config.global_config.colorscheme.overlay_bg)

	modal_w := min(space.w - 20 * scale, 500.0 * scale)
	modal_h: f32 = 160.0 * scale
	modal_x := space.x + (space.w - modal_w) / 2
	modal_y := space.y + (space.h - modal_h) / 2

	modal_rect := render.rect{modal_x, modal_y, modal_w, modal_h}
	render.fill_rect(r, modal_rect, config.global_config.colorscheme.popup_bg)
	render.draw_rect(r, modal_rect, 2.0, config.global_config.colorscheme.popup_border)

	popup_font_size := 18.0 * scale
	popup_char_size := render.get_cell_size(r, popup_font_size)

	msg_pos := [2]f32{modal_x + 15 * scale, modal_y + 25 * scale}
	render.draw_text(
		r,
		fe.modal.message,
		msg_pos,
		config.global_config.colorscheme.popup_text_sel,
		popup_font_size,
	)

	if fe.modal.type == .DeleteConfirm {
		draw_modal_delete_confirm(r, modal_rect, scale, popup_font_size)
	} else {
		draw_modal_input_prompt(r, fe, modal_rect, scale, popup_font_size, popup_char_size)
	}
}

draw_modal_delete_confirm :: proc(
	r: ^render.renderer_state,
	modal_rect: render.rect,
	scale, popup_font_size: f32,
) {
	actions_pos := [2]f32{modal_rect.x + 15 * scale, modal_rect.y + 80 * scale}
	render.draw_text(
		r,
		"Press [y] Yes  or  [n] No",
		actions_pos,
		config.global_config.colorscheme.popup_text,
		popup_font_size,
	)
}

draw_modal_input_prompt :: proc(
	r: ^render.renderer_state,
	fe: ^file_explorer,
	modal_rect: render.rect,
	scale, popup_font_size: f32,
	popup_char_size: [2]f32,
) {
	input_box_y := modal_rect.y + 70 * scale
	input_box_h := popup_char_size.y + 12 * scale
	input_box := render.rect {
		modal_rect.x + 15 * scale,
		input_box_y,
		modal_rect.w - 30 * scale,
		input_box_h,
	}
	render.fill_rect(r, input_box, config.global_config.colorscheme.bg)
	render.draw_rect(r, input_box, 1.0, config.global_config.colorscheme.popup_border)

	input_str := string(fe.modal.input[:])
	text_pos := [2]f32{modal_rect.x + 22 * scale, input_box_y + 6 * scale}
	render.draw_text(r, input_str, text_pos, config.global_config.colorscheme.fg, popup_font_size)

	rune_count := 0
	for _, index in input_str {
		if index >= fe.modal.cursor do break
		rune_count += 1
	}
	cursor_x := modal_rect.x + 22 * scale + f32(rune_count) * popup_char_size.x
	cursor_rect := render.rect{cursor_x, input_box_y + 6 * scale, 2.0, popup_char_size.y}
	render.fill_rect(r, cursor_rect, config.global_config.colorscheme.cursor_solid)
}
