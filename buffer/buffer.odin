package buffer

import "core:os"
import "core:strings"

buffer_flag :: enum {
	Is_Updated,
}

buffer_flags :: bit_set[buffer_flag]

buffer :: struct {
	lines:     [dynamic][dynamic]u8,
	path:      string,
	file_type: string,
	flags:     buffer_flags,
}

init :: proc(b: ^buffer) {
	b.lines = make([dynamic][dynamic]u8, 0, 16)
	append(&b.lines, make([dynamic]u8))
	b.path = ""
	b.file_type = ""
	b.flags = {}
}

destroy :: proc(b: ^buffer) {
	for line in b.lines {
		delete(line)
	}
	delete(b.lines)
	if len(b.path) > 0 do delete(b.path)
	b.file_type = ""
}

find_line_index :: proc(b: ^buffer, offset: int) -> int {
	curr_off := 0
	for line_idx in 0 ..< len(b.lines) {
		line_len := len(b.lines[line_idx])
		if offset >= curr_off && offset <= curr_off + line_len {
			return line_idx
		}
		curr_off += line_len + 1
	}
	if len(b.lines) > 0 {
		return len(b.lines) - 1
	}
	return 0
}

insert_bytes_at :: proc(line: ^[dynamic]u8, col: int, bytes: []u8) {
	n := len(bytes)
	if n == 0 do return
	old_len := len(line)
	resize(line, old_len + n)
	copy(line[col + n:], line[col:old_len])
	copy(line[col:], bytes)
}

insert :: proc(b: ^buffer, offset: int, text: string) {
	if len(text) == 0 do return
	if offset < 0 || offset > len_bytes(b) do return

	b.flags += {.Is_Updated}

	line_idx, col_idx, ok := offset_to_position(b, offset)
	if !ok {
		line_idx = len(b.lines) - 1
		col_idx = len(b.lines[line_idx])
	}

	has_newline := false
	for i in 0 ..< len(text) {
		if text[i] == '\n' {
			has_newline = true
			break
		}
	}

	if !has_newline {
		insert_bytes_at(&b.lines[line_idx], col_idx, transmute([]u8)text)
		return
	}

	right_part := make([dynamic]u8)
	defer delete(right_part)
	append(&right_part, ..b.lines[line_idx][col_idx:])
	resize(&b.lines[line_idx], col_idx)

	curr_line_idx := line_idx
	start := 0
	for i := 0; i <= len(text); i += 1 {
		if i == len(text) || text[i] == '\n' {
			part := text[start:i]
			if curr_line_idx == line_idx {
				append(&b.lines[curr_line_idx], ..transmute([]u8)part)
			} else {
				new_line := make([dynamic]u8)
				append(&new_line, ..transmute([]u8)part)
				inject_at(&b.lines, curr_line_idx, new_line)
			}
			curr_line_idx += 1
			start = i + 1
		}
	}

	last_line_idx := curr_line_idx - 1
	append(&b.lines[last_line_idx], ..right_part[:])
}

delete_bytes_at :: proc(line: ^[dynamic]u8, col, length: int) {
	if length <= 0 do return
	old_len := len(line)
	copy(line[col:], line[col + length:])
	resize(line, old_len - length)
}

remove_lines :: proc(lines: ^[dynamic][dynamic]u8, index: int, count: int) {
	if count <= 0 do return
	old_len := len(lines)
	copy(lines[index:], lines[index + count:])
	resize(lines, old_len - count)
}

remove :: proc(b: ^buffer, offset, length: int) {
	if offset < 0 || length <= 0 do return
	total_len := len_bytes(b)
	if offset + length > total_len do return

	b.flags += {.Is_Updated}

	start_line, start_col, ok1 := offset_to_position(b, offset)
	end_line, end_col, ok2 := offset_to_position(b, offset + length)
	if !ok1 || !ok2 do return

	if start_line == end_line {
		delete_bytes_at(&b.lines[start_line], start_col, length)
		return
	}

	suffix := make([dynamic]u8)
	defer delete(suffix)
	append(&suffix, ..b.lines[end_line][end_col:])

	resize(&b.lines[start_line], start_col)
	append(&b.lines[start_line], ..suffix[:])

	num_lines_to_remove := end_line - start_line
	for idx := start_line + 1; idx <= end_line; idx += 1 {
		delete(b.lines[idx])
	}
	remove_lines(&b.lines, start_line + 1, num_lines_to_remove)
}

line_count :: proc(b: ^buffer) -> int {
	return len(b.lines)
}

get_line :: proc(b: ^buffer, line_idx: int) -> string {
	if line_idx < 0 || line_idx >= len(b.lines) {
		return ""
	}
	return string(b.lines[line_idx][:])
}

offset_at_position :: proc(b: ^buffer, line, col: int) -> int {
	if line < 0 || line >= len(b.lines) {
		return 0
	}
	start_offset := get_line_start(b, line)
	return min(start_offset + col, start_offset + len(b.lines[line]))
}

get_line_start :: proc(b: ^buffer, line_idx: int) -> int {
	if line_idx < 0 || line_idx >= len(b.lines) {
		return 0
	}
	offset := 0
	for i in 0 ..< line_idx {
		offset += len(b.lines[i]) + 1
	}
	return offset
}

get_line_end :: proc(b: ^buffer, line_idx: int) -> int {
	if line_idx < 0 || line_idx >= len(b.lines) {
		return 0
	}
	start_offset := get_line_start(b, line_idx)
	return start_offset + len(b.lines[line_idx])
}

to_string :: proc(b: ^buffer, allocator := context.allocator) -> string {
	out: [dynamic]u8
	defer delete(out)

	for i in 0 ..< len(b.lines) {
		append(&out, ..b.lines[i][:])
		if i < len(b.lines) - 1 {
			append(&out, '\n')
		}
	}

	return strings.clone(string(out[:]), allocator)
}

load_from_file :: proc(b: ^buffer, path: string) -> bool {
	data, ok := os.read_entire_file(path)
	if !ok do return false
	defer delete(data)

	destroy(b)
	b.lines = make([dynamic][dynamic]u8, 0, 16)

	start := 0
	for i := 0; i <= len(data); i += 1 {
		if i == len(data) || data[i] == '\n' {
			line := make([dynamic]u8, i - start)
			copy(line[:], data[start:i])
			append(&b.lines, line)
			start = i + 1
		}
	}

	b.path = strings.clone(path)
	b.file_type = ""
	b.flags = {}

	return true
}

save_to_file :: proc(b: ^buffer, path: string) -> bool {
	out: [dynamic]u8
	defer delete(out)

	for i in 0 ..< len(b.lines) {
		append(&out, ..b.lines[i][:])
		if i < len(b.lines) - 1 {
			append(&out, '\n')
		}
	}

	ok := os.write_entire_file(path, out[:])
	if ok {
		b.flags -= {.Is_Updated}
	}
	return ok
}

len_bytes :: proc(b: ^buffer) -> int {
	if len(b.lines) == 0 do return 0
	total := 0
	for i in 0 ..< len(b.lines) {
		total += len(b.lines[i])
		if i < len(b.lines) - 1 {
			total += 1
		}
	}
	return total
}

offset_to_position :: proc(b: ^buffer, offset: int) -> (line: int, col: int, ok: bool) {
	curr_off := 0
	for line_idx in 0 ..< len(b.lines) {
		line_len := len(b.lines[line_idx])
		if offset >= curr_off && offset <= curr_off + line_len {
			return line_idx, offset - curr_off, true
		}
		curr_off += line_len + 1
	}
	return 0, 0, false
}

position_to_offset :: proc(b: ^buffer, line: int, col: int) -> (offset: int, ok: bool) {
	if line < 0 || line >= len(b.lines) do return 0, false
	offset = 0
	for i in 0 ..< line {
		offset += len(b.lines[i]) + 1
	}
	if col < 0 || col > len(b.lines[line]) do return 0, false
	return offset + col, true
}
