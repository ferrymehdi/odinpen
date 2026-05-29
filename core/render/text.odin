package render

import "core:math"
import "core:unicode/utf8"

draw_text :: proc(
	r: ^renderer_state,
	text: string,
	pos: [2]f32,
	color: [4]f32,
	target_size: f32 = 0.0,
	style: font_style = .Regular,
	tab_size: int = 4,
) {
	dpi := r.dpi_scale > 0 ? r.dpi_scale : 1.0
	x := math.floor(pos.x * dpi + 0.5) / dpi

	actual_size := target_size
	if actual_size <= 0.0 {
		actual_size = 18.0
	}

	ascent, descent, line_gap := get_font_v_metrics(r, actual_size, style)

	y := math.floor((pos.y + (actual_size + ascent - (-descent)) / 2) * dpi + 0.5) / dpi

	it := text
	for len(it) > 0 {
		ch, rune_size := utf8.decode_rune_in_string(it)
		it = it[rune_size:]

		if ch == '\t' {
			x += f32(tab_size) * get_cell_size(r, actual_size).x
			continue
		}

		if cg, ok := get_or_render_glyph(r, ch, actual_size, style); ok {
			p0 := [2]f32{x + cg.x0, y + cg.y0}
			p1 := [2]f32{x + cg.x1, y + cg.y0}
			p2 := [2]f32{x + cg.x1, y + cg.y1}
			p3 := [2]f32{x + cg.x0, y + cg.y1}

			uv0 := [2]f32{cg.u0, cg.v0}
			uv1 := [2]f32{cg.u1, cg.v0}
			uv2 := [2]f32{cg.u1, cg.v1}
			uv3 := [2]f32{cg.u0, cg.v1}

			push_quad(r, p0, p1, p2, p3, color, uv0, uv1, uv2, uv3, 1.0)
			x += get_cell_size(r, actual_size).x
		} else {
			size := get_cell_size(r, actual_size)
			py := math.floor(pos.y + 0.5)
			p0 := [2]f32{x, py}
			p1 := [2]f32{x + size.x, py}
			p2 := [2]f32{x + size.x, py + size.y}
			p3 := [2]f32{x, py + size.y}

			push_quad(r, p0, p1, p2, p3, color, {0, 0}, {1, 0}, {1, 1}, {0, 1}, 0.0)
			x += size.x
		}
	}
}
