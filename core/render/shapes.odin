package render

rect :: struct {
	x, y, w, h: f32,
}

circle :: struct {
	center: [2]f32,
	radius: f32,
}

line :: struct {
	p1, p2:    [2]f32,
	thickness: f32,
}

draw_rect :: proc(r: ^renderer_state, rect: rect, thickness: f32, color: [4]f32) {
	p0 := [2]f32{rect.x, rect.y}
	p1 := [2]f32{rect.x + rect.w, rect.y}
	p2 := [2]f32{rect.x + rect.w, rect.y + rect.h}
	p3 := [2]f32{rect.x, rect.y + rect.h}
	push_quad(
		r,
		p0,
		p1,
		p2,
		p3,
		color,
		{0, 0},
		{1, 0},
		{1, 1},
		{0, 1},
		4.0 + thickness / 1000.0,
		{rect.w, rect.h},
	)
}

fill_rect :: proc(r: ^renderer_state, rect: rect, color: [4]f32) {
	p0 := [2]f32{rect.x, rect.y}
	p1 := [2]f32{rect.x + rect.w, rect.y}
	p2 := [2]f32{rect.x + rect.w, rect.y + rect.h}
	p3 := [2]f32{rect.x, rect.y + rect.h}
	push_quad(r, p0, p1, p2, p3, color, {0, 0}, {1, 0}, {1, 1}, {0, 1}, 0)
}

draw_circle :: proc(r: ^renderer_state, circle: circle, thickness: f32, color: [4]f32) {
	p0 := circle.center + {-circle.radius, -circle.radius}
	p1 := circle.center + {circle.radius, -circle.radius}
	p2 := circle.center + {circle.radius, circle.radius}
	p3 := circle.center + {-circle.radius, circle.radius}
	t := thickness / circle.radius
	push_quad(r, p0, p1, p2, p3, color, {-1, -1}, {1, -1}, {1, 1}, {-1, 1}, 2, {t, 0})
}

fill_circle :: proc(r: ^renderer_state, circle: circle, color: [4]f32) {
	draw_circle(r, circle, 0, color)
}

draw_line :: proc(r: ^renderer_state, line: line, color: [4]f32) {
	dir := line.p2 - line.p1
	len_sq := dir.x * dir.x + dir.y * dir.y
	if len_sq < 0.0001 do return

	half_t := line.thickness * 0.5

	p0 := line.p1
	d0 := line.p2
	uv0 := [2]f32{0, half_t}

	p1 := line.p2
	d1 := line.p1
	uv1 := [2]f32{1, half_t}

	p2 := line.p2
	d2 := line.p1
	uv2 := [2]f32{1, -half_t}

	p3 := line.p1
	d3 := line.p2
	uv3 := [2]f32{0, -half_t}

	push_quad_ext(r, p0, p1, p2, p3, color, uv0, uv1, uv2, uv3, 3.0, d0, d1, d2, d3)
}
