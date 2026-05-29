package render

import "core:fmt"
import "core:strings"
import GL "vendor:OpenGL"

VS_SOURCE :: `#version 330 core
layout (location = 0) in vec2 aPos;
layout (location = 1) in vec4 aColor;
layout (location = 2) in vec2 aUv;
layout (location = 3) in float aMode;
layout (location = 4) in vec2 aData;

uniform mat4 projection;

out vec4 vColor;
out vec2 vUv;
out float vMode;
out vec2 vData;

void main() {
    vec2 final_pos = aPos;
    float mode = floor(aMode);

    if (mode == 3.0) { // GPU-expanded Line
        vec2 dir;
        if (aUv.x < 0.5) {
            dir = aData - aPos;
        } else {
            dir = aPos - aData;
        }
        float len = length(dir);
        if (len > 0.0001) {
            vec2 norm = vec2(-dir.y, dir.x) / len;
            final_pos = aPos + norm * aUv.y;
        }
    }

    gl_Position = projection * vec4(final_pos, 0.0, 1.0);
    vColor = aColor;
    vUv = aUv;
    vMode = aMode;
    vData = aData;
}`

FS_SOURCE :: `#version 330 core
out vec4 FragColor;

in vec4 vColor;
in vec2 vUv;
in float vMode;
in vec2 vData;

uniform sampler2D fontTexture;

void main() {
    float mode = floor(vMode);

    if (vMode < 0.5) { // Solid
        FragColor = vColor;
    } else if (vMode < 1.5) { // Text
        float alpha = texture(fontTexture, vUv).r;
        FragColor = vec4(vColor.rgb, vColor.a * alpha);
    } else if (vMode < 2.5) { // circle
        float dist = length(vUv);
        float radius = 1.0;
        float thickness = vData.x; // thickness/radius ratio

        float alpha = 0.0;
        float smoothing = 0.02; // Small smoothing for anti-aliasing

        if (thickness <= 0.0) {
            // Filled
            alpha = 1.0 - smoothstep(radius - smoothing, radius, dist);
        } else {
            // Outline
            float outer = 1.0 - smoothstep(radius - smoothing, radius, dist);
            float inner = 1.0 - smoothstep(radius - thickness - smoothing, radius - thickness, dist);
            alpha = outer - inner;
        }

        if (alpha <= 0.0) discard;
        FragColor = vec4(vColor.rgb, vColor.a * alpha);
    } else if (mode == 3.0) { // Line
        FragColor = vColor;
    } else if (mode == 4.0) { // Rect Outline
        float thickness = (vMode - 4.0) * 1000.0;
        vec2 local_pos = vUv * vData;
        if (local_pos.x < thickness || local_pos.x > vData.x - thickness ||
            local_pos.y < thickness || local_pos.y > vData.y - thickness) {
            FragColor = vColor;
        } else {
            discard;
        }
    } else {
        FragColor = vColor;
    }
}`

compile_shader :: proc(source: string, shader_type: u32) -> u32 {
	shader := GL.CreateShader(shader_type)
	cs := strings.clone_to_cstring(source, context.temp_allocator)
	GL.ShaderSource(shader, 1, &cs, nil)
	GL.CompileShader(shader)

	success: i32
	GL.GetShaderiv(shader, GL.COMPILE_STATUS, &success)
	if success == 0 {
		log_len: i32
		GL.GetShaderiv(shader, GL.INFO_LOG_LENGTH, &log_len)
		log_str := make([]u8, log_len)
		defer delete(log_str)
		GL.GetShaderInfoLog(shader, log_len, nil, &log_str[0])
		fmt.eprintf("Shader error (%v): %s\n", shader_type, string(log_str))
		GL.DeleteShader(shader)
		return 0
	}
	return shader
}

create_shader_program :: proc(vs_source, fs_source: string) -> u32 {
	vs := compile_shader(vs_source, GL.VERTEX_SHADER)
	fs := compile_shader(fs_source, GL.FRAGMENT_SHADER)
	prog := GL.CreateProgram()
	GL.AttachShader(prog, vs); GL.AttachShader(prog, fs)
	GL.LinkProgram(prog)
	GL.DeleteShader(vs); GL.DeleteShader(fs)

	link_success: i32
	GL.GetProgramiv(prog, GL.LINK_STATUS, &link_success)
	if link_success == 0 {
		log_len: i32
		GL.GetProgramiv(prog, GL.INFO_LOG_LENGTH, &log_len)
		log_str := make([]u8, log_len)
		defer delete(log_str)
		GL.GetProgramInfoLog(prog, log_len, nil, &log_str[0])
		fmt.eprintf("Shader link error: %s\n", string(log_str))
		GL.DeleteProgram(prog)
		return 0
	}
	return prog
}
