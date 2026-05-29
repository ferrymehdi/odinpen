package render

import "../../config"
import c "core:c"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import GL "vendor:OpenGL"
import "vendor:stb/truetype"

vertex :: struct {
	pos:   [2]f32,
	color: [4]f32,
	uv:    [2]f32,
	mode:  f32,
	data:  [2]f32,
}

font_style :: enum {
	Regular,
	Bold,
	Italic,
	Bold_Italic,
}

glyph_key :: struct {
	r:     rune,
	size:  f32,
	style: font_style,
}

cached_glyph :: struct {
	x0, y0, x1, y1: f32,
	u0, v0, u1, v1: f32,
	advance:        f32,
	lsb:            f32,
}

renderer_state :: struct {
	vao, vbo, ebo:    u32,
	shader:           u32,
	projection_loc:   i32,
	vertices:         [dynamic]vertex,
	indices:          [dynamic]u32,
	font_texture:     u32,
	font_size:        f32,
	dpi_scale:        f32,
	projection:       matrix[4, 4]f32,
	in_frame:         bool,
	font_info:        [font_style]truetype.fontinfo,
	font_buffers:     [font_style][]u8,
	glyph_cache:      map[glyph_key]cached_glyph,
	atlas_width:      int,
	atlas_height:     int,
	atlas_cursor_x:   int,
	atlas_cursor_y:   int,
	atlas_row_height: int,
}

get_cell_size :: proc(r: ^renderer_state, font_size: f32) -> [2]f32 {
	rounded_size := math.floor(font_size + 0.5)
	if rounded_size < 1.0 do rounded_size = 1.0

	font := &r.font_info[.Regular]
	if font.data == nil do return {rounded_size * 0.6, rounded_size}

	dpi := r.dpi_scale > 0 ? r.dpi_scale : 1.0
	physical_size := math.floor(rounded_size * dpi + 0.5)
	if physical_size < 1.0 do physical_size = 1.0

	scale := truetype.ScaleForPixelHeight(font, physical_size)
	advance, lsb: c.int
	truetype.GetCodepointHMetrics(font, 'M', &advance, &lsb)

	physical_width := math.floor(f32(advance) * scale + 0.5)
	return {physical_width / dpi, physical_size / dpi}
}

get_font_v_metrics :: proc(
	r: ^renderer_state,
	size: f32,
	style: font_style = .Regular,
) -> (
	ascent, descent, line_gap: f32,
) {
	font := &r.font_info[style]
	if font.data == nil {
		font = &r.font_info[.Regular]
		if font.data == nil do return size, 0, 0
	}

	scale := truetype.ScaleForPixelHeight(font, size)
	asc, desc, lg: c.int
	truetype.GetFontVMetrics(font, &asc, &desc, &lg)

	return f32(asc) * scale, f32(desc) * scale, f32(lg) * scale
}

clear_glyph_cache :: proc(r: ^renderer_state) {
	clear(&r.glyph_cache)
	r.atlas_cursor_x = 1
	r.atlas_cursor_y = 1
	r.atlas_row_height = 0

	empty_pixels := make([]u8, r.atlas_width * r.atlas_height)
	defer delete(empty_pixels)

	GL.BindTexture(GL.TEXTURE_2D, r.font_texture)
	GL.PixelStorei(GL.UNPACK_ALIGNMENT, 1)
	GL.TexSubImage2D(
		GL.TEXTURE_2D,
		0,
		0,
		0,
		i32(r.atlas_width),
		i32(r.atlas_height),
		GL.RED,
		GL.UNSIGNED_BYTE,
		raw_data(empty_pixels),
	)
}

get_or_render_glyph :: proc(
	r: ^renderer_state,
	ch: rune,
	size: f32,
	style: font_style,
) -> (
	cached_glyph,
	bool,
) {
	rounded_size := math.floor(size + 0.5)
	if rounded_size < 1.0 do rounded_size = 1.0

	key := glyph_key{ch, rounded_size, style}
	if key in r.glyph_cache {
		return r.glyph_cache[key], true
	}

	font := &r.font_info[style]
	if font.data == nil {
		font = &r.font_info[.Regular]
		if font.data == nil do return cached_glyph{}, false
	}

	dpi := r.dpi_scale > 0 ? r.dpi_scale : 1.0
	physical_size := math.floor(rounded_size * dpi + 0.5)
	if physical_size < 1.0 do physical_size = 1.0

	scale := truetype.ScaleForPixelHeight(font, physical_size)

	ix0, iy0, ix1, iy1: c.int
	truetype.GetCodepointBitmapBox(font, ch, scale, scale, &ix0, &iy0, &ix1, &iy1)

	w := int(ix1 - ix0)
	h := int(iy1 - iy0)

	advance, lsb: c.int
	truetype.GetCodepointHMetrics(font, ch, &advance, &lsb)

	pad := 1
	needed_w := w + pad
	needed_h := h + pad

	if r.atlas_cursor_x + needed_w > r.atlas_width {
		r.atlas_cursor_y += r.atlas_row_height + pad
		r.atlas_cursor_x = pad
		r.atlas_row_height = 0
	}

	if r.atlas_cursor_y + needed_h > r.atlas_height {
		clear_glyph_cache(r)
		r.atlas_cursor_x = pad
		r.atlas_cursor_y = pad
		r.atlas_row_height = 0
	}

	x := r.atlas_cursor_x
	y := r.atlas_cursor_y

	if h > r.atlas_row_height {
		r.atlas_row_height = h
	}
	r.atlas_cursor_x += needed_w

	if w > 0 && h > 0 {
		glyph_pixels := make([]u8, w * h, context.temp_allocator)
		truetype.MakeCodepointBitmap(
			font,
			raw_data(glyph_pixels),
			i32(w),
			i32(h),
			i32(w),
			scale,
			scale,
			ch,
		)

		GL.BindTexture(GL.TEXTURE_2D, r.font_texture)
		GL.PixelStorei(GL.UNPACK_ALIGNMENT, 1)
		GL.TexSubImage2D(
			GL.TEXTURE_2D,
			0,
			i32(x),
			i32(y),
			i32(w),
			i32(h),
			GL.RED,
			GL.UNSIGNED_BYTE,
			raw_data(glyph_pixels),
		)
	}

	cg := cached_glyph {
		x0      = f32(ix0) / dpi,
		y0      = f32(iy0) / dpi,
		x1      = f32(ix1) / dpi,
		y1      = f32(iy1) / dpi,
		u0      = f32(x) / f32(r.atlas_width),
		v0      = f32(y) / f32(r.atlas_height),
		u1      = f32(x + w) / f32(r.atlas_width),
		v1      = f32(y + h) / f32(r.atlas_height),
		advance = (f32(advance) * scale) / dpi,
		lsb     = (f32(lsb) * scale) / dpi,
	}

	r.glyph_cache[key] = cg
	return cg, true
}

init :: proc(r: ^renderer_state) {
	r.vertices = make([dynamic]vertex, 0, 1024)
	r.indices = make([dynamic]u32, 0, 2048)

	r.shader = create_shader_program(VS_SOURCE, FS_SOURCE)
	r.projection_loc = GL.GetUniformLocation(r.shader, "projection")

	GL.GenVertexArrays(1, &r.vao)
	GL.GenBuffers(1, &r.vbo)
	GL.GenBuffers(1, &r.ebo)

	GL.BindVertexArray(r.vao)
	GL.BindBuffer(GL.ARRAY_BUFFER, r.vbo)
	GL.BindBuffer(GL.ELEMENT_ARRAY_BUFFER, r.ebo)

	stride := i32(size_of(vertex))
	GL.EnableVertexAttribArray(
		0,
	); GL.VertexAttribPointer(0, 2, GL.FLOAT, GL.FALSE, stride, offset_of(vertex, pos))
	GL.EnableVertexAttribArray(
		1,
	); GL.VertexAttribPointer(1, 4, GL.FLOAT, GL.FALSE, stride, offset_of(vertex, color))
	GL.EnableVertexAttribArray(
		2,
	); GL.VertexAttribPointer(2, 2, GL.FLOAT, GL.FALSE, stride, offset_of(vertex, uv))
	GL.EnableVertexAttribArray(
		3,
	); GL.VertexAttribPointer(3, 1, GL.FLOAT, GL.FALSE, stride, offset_of(vertex, mode))
	GL.EnableVertexAttribArray(
		4,
	); GL.VertexAttribPointer(4, 2, GL.FLOAT, GL.FALSE, stride, offset_of(vertex, data))

	GL.BindVertexArray(0)

	r.glyph_cache = make(map[glyph_key]cached_glyph)
	r.atlas_width = 2048
	r.atlas_height = 2048
	r.atlas_cursor_x = 1
	r.atlas_cursor_y = 1
	r.atlas_row_height = 0

	GL.GenTextures(1, &r.font_texture)
	GL.BindTexture(GL.TEXTURE_2D, r.font_texture)

	empty_pixels := make([]u8, r.atlas_width * r.atlas_height)
	defer delete(empty_pixels)

	GL.TexImage2D(
		GL.TEXTURE_2D,
		0,
		GL.RED,
		i32(r.atlas_width),
		i32(r.atlas_height),
		0,
		GL.RED,
		GL.UNSIGNED_BYTE,
		raw_data(empty_pixels),
	)
	GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.LINEAR)
	GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.LINEAR)
	GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.CLAMP_TO_EDGE)
	GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.CLAMP_TO_EDGE)

	style_paths := [font_style]string {
		.Regular     = config.global_config.font_regular,
		.Bold        = config.global_config.font_bold,
		.Italic      = config.global_config.font_italic,
		.Bold_Italic = config.global_config.font_bold_italic,
	}

	for style in font_style {
		path := style_paths[style]
		data, ok := os.read_entire_file(path)
		if !ok {
			fmt.eprintf("Warning: failed to load font style %v from %s\n", style, path)
			if style != .Regular {
				r.font_buffers[style] = nil
				r.font_info[style] = r.font_info[.Regular]
			}
		} else {
			r.font_buffers[style] = data
			ok_init := truetype.InitFont(&r.font_info[style], raw_data(data), 0)
			if !ok_init {
				fmt.eprintf("Warning: failed to init font style %v\n", style)
				if style != .Regular {
					r.font_info[style] = r.font_info[.Regular]
				}
			}
		}
	}

	r.font_size = 18.0
	r.dpi_scale = 1.0
	r.projection = matrix_ortho(0, 640, 480, 0, -1, 1)
}

matrix_ortho :: proc(left, right, bottom, top, near, far: f32) -> matrix[4, 4]f32 {
	m: matrix[4, 4]f32
	m[0, 0] = 2 / (right - left)
	m[1, 1] = 2 / (top - bottom)
	m[2, 2] = -2 / (far - near)
	m[0, 3] = -(right + left) / (right - left)
	m[1, 3] = -(top + bottom) / (top - bottom)
	m[2, 3] = -(far + near) / (far - near)
	m[3, 3] = 1
	return m
}

render_set_projection :: proc(r: ^renderer_state, projection: [16]f32, dpi_scale: f32 = 1.0) {
	p := projection
	mem.copy(&r.projection, &p, size_of(matrix[4, 4]f32))
	if r.dpi_scale != dpi_scale {
		r.dpi_scale = dpi_scale
		clear_glyph_cache(r)
	}
}

begin_frame :: proc(r: ^renderer_state) {
	clear(&r.vertices)
	clear(&r.indices)
	r.in_frame = true
}

end_frame :: proc(r: ^renderer_state) {
	flush(r)
	r.in_frame = false
}

flush :: proc(r: ^renderer_state) {
	if len(r.vertices) == 0 do return

	GL.UseProgram(r.shader)
	GL.UniformMatrix4fv(r.projection_loc, 1, GL.FALSE, &r.projection[0, 0])

	GL.BindVertexArray(r.vao)
	GL.BindBuffer(GL.ARRAY_BUFFER, r.vbo)
	GL.BufferData(
		GL.ARRAY_BUFFER,
		len(r.vertices) * size_of(vertex),
		raw_data(r.vertices),
		GL.STREAM_DRAW,
	)
	GL.BindBuffer(GL.ELEMENT_ARRAY_BUFFER, r.ebo)
	GL.BufferData(
		GL.ELEMENT_ARRAY_BUFFER,
		len(r.indices) * size_of(u32),
		raw_data(r.indices),
		GL.STREAM_DRAW,
	)

	GL.Enable(GL.BLEND)
	GL.BlendFunc(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)

	GL.ActiveTexture(GL.TEXTURE0)
	GL.BindTexture(GL.TEXTURE_2D, r.font_texture)

	GL.DrawElements(GL.TRIANGLES, i32(len(r.indices)), GL.UNSIGNED_INT, nil)
	GL.BindVertexArray(0)

	clear(&r.vertices)
	clear(&r.indices)
}

push_quad :: proc(
	r: ^renderer_state,
	p0, p1, p2, p3: [2]f32,
	color: [4]f32,
	uv0, uv1, uv2, uv3: [2]f32,
	mode: f32,
	data: [2]f32 = {0, 0},
) {

	base := u32(len(r.vertices))

	append(&r.vertices, vertex{p0, color, uv0, mode, data})

	append(&r.vertices, vertex{p1, color, uv1, mode, data})

	append(&r.vertices, vertex{p2, color, uv2, mode, data})

	append(&r.vertices, vertex{p3, color, uv3, mode, data})

	append(&r.indices, base + 0, base + 1, base + 2, base + 0, base + 2, base + 3)

	if !r.in_frame do flush(r)

}

push_quad_ext :: proc(
	r: ^renderer_state,
	p0, p1, p2, p3: [2]f32,
	color: [4]f32,
	uv0, uv1, uv2, uv3: [2]f32,
	mode: f32,
	d0, d1, d2, d3: [2]f32,
) {
	base := u32(len(r.vertices))
	append(&r.vertices, vertex{p0, color, uv0, mode, d0})
	append(&r.vertices, vertex{p1, color, uv1, mode, d1})
	append(&r.vertices, vertex{p2, color, uv2, mode, d2})
	append(&r.vertices, vertex{p3, color, uv3, mode, d3})
	append(&r.indices, base + 0, base + 1, base + 2, base + 0, base + 2, base + 3)

	if !r.in_frame do flush(r)
}

destroy :: proc(r: ^renderer_state) {
	delete(r.vertices)
	delete(r.indices)

	if r.font_texture != 0 {
		GL.DeleteTextures(1, &r.font_texture)
	}

	for style in font_style {
		if r.font_buffers[style] != nil {
			delete(r.font_buffers[style])
		}
	}

	delete(r.glyph_cache)

	vao := r.vao
	vbo := r.vbo
	ebo := r.ebo
	GL.DeleteVertexArrays(1, &vao)
	GL.DeleteBuffers(1, &vbo)
	GL.DeleteBuffers(1, &ebo)
	GL.DeleteProgram(r.shader)
}
