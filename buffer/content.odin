package buffer

import "core:unicode/utf8"

get_char_class :: proc(r: rune, big_word: bool) -> int {
	if r == ' ' || r == '\t' || r == '\n' || r == '\r' do return 0
	if big_word do return 1
	if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' {
		return 1
	}
	return 2
}

decode_prev_rune :: proc(b: ^buffer, pos: int) -> (rune, int) {
	if pos <= 0 do return 0, 0
	line, col, ok := offset_to_position(b, pos)
	if !ok do return 0, 0
	if col == 0 {
		if line == 0 do return 0, 0
		return '\n', 1
	}
	start := col - 1
	for start >= 0 && (b.lines[line][start] & 0xC0) == 0x80 {
		start -= 1
	}
	if start < 0 do return 0, 0
	return utf8.decode_rune(b.lines[line][start:col])
}

decode_rune_at :: proc(b: ^buffer, pos: int) -> (rune, int) {
	line, col, ok := offset_to_position(b, pos)
	if !ok do return 0, 0
	if col == len(b.lines[line]) {
		return '\n', 1
	}
	return utf8.decode_rune(b.lines[line][col:])
}

get_next_word_offset :: proc(b: ^buffer, start_offset: int, big_word: bool = false) -> int {
	total_len := len_bytes(b)
	if total_len == 0 do return start_offset

	idx := start_offset
	if idx >= total_len do return total_len

	r, size := decode_rune_at(b, idx)
	if size == 0 do return idx

	start_class := get_char_class(r, big_word)

	if start_class != 0 {
		for idx < total_len {
			next_r, next_size := decode_rune_at(b, idx)
			if next_size == 0 do break
			if get_char_class(next_r, big_word) != start_class {
				break
			}
			idx += next_size
		}
	}

	for idx < total_len {
		next_r, next_size := decode_rune_at(b, idx)
		if next_size == 0 do break
		if get_char_class(next_r, big_word) != 0 {
			break
		}
		idx += next_size
	}

	return idx
}

get_prev_word_offset :: proc(b: ^buffer, start_offset: int, big_word: bool = false) -> int {
	idx := start_offset
	if idx <= 0 do return 0

	for idx > 0 {
		r, sz := decode_prev_rune(b, idx)
		if sz == 0 do break
		if get_char_class(r, big_word) != 0 {
			break
		}
		idx -= sz
	}

	if idx <= 0 do return 0

	r, sz := decode_prev_rune(b, idx)
	if sz == 0 do return idx
	word_class := get_char_class(r, big_word)

	for idx > 0 {
		prev_r, prev_sz := decode_prev_rune(b, idx)
		if prev_sz == 0 do break
		if get_char_class(prev_r, big_word) != word_class {
			break
		}
		idx -= prev_sz
	}

	return idx
}

get_end_of_word_offset :: proc(b: ^buffer, start_offset: int, big_word: bool = false) -> int {
	total_len := len_bytes(b)
	if total_len == 0 do return start_offset

	idx := start_offset
	if idx >= total_len do return total_len

	r, sz := decode_rune_at(b, idx)
	if sz == 0 do return idx
	start_class := get_char_class(r, big_word)

	next_idx := idx + sz
	next_r, next_sz := decode_rune_at(b, next_idx)

	if start_class != 0 && next_sz > 0 && get_char_class(next_r, big_word) == start_class {
		idx = next_idx
		for idx < total_len {
			curr_r, curr_sz := decode_rune_at(b, idx)
			if curr_sz == 0 do break
			if get_char_class(curr_r, big_word) != start_class {
				break
			}
			idx += curr_sz
		}
	} else {
		if start_class != 0 {
			for idx < total_len {
				curr_r, curr_sz := decode_rune_at(b, idx)
				if curr_sz == 0 do break
				if get_char_class(curr_r, big_word) != start_class {
					break
				}
				idx += curr_sz
			}
		}

		for idx < total_len {
			curr_r, curr_sz := decode_rune_at(b, idx)
			if curr_sz == 0 do break
			if get_char_class(curr_r, big_word) != 0 {
				break
			}
			idx += curr_sz
		}

		if idx < total_len {
			curr_r, curr_sz := decode_rune_at(b, idx)
			word_class := get_char_class(curr_r, big_word)

			for idx < total_len {
				curr_r2, curr_sz2 := decode_rune_at(b, idx)
				if curr_sz2 == 0 do break
				if get_char_class(curr_r2, big_word) != word_class {
					break
				}
				idx += curr_sz2
			}
		}
	}

	if idx > start_offset {
		_, sz_prev := decode_prev_rune(b, idx)
		if sz_prev > 0 {
			idx = idx - sz_prev
		}
	}

	return idx
}

get_word_at_offset :: proc(
	b: ^buffer,
	offset: int,
	big_word: bool = false,
) -> (
	word: string,
	start_offset: int,
	class: int,
	ok: bool,
) {
	total_len := len_bytes(b)
	if total_len == 0 do return "", 0, 0, false
	if offset < 0 || offset >= total_len do return "", 0, 0, false

	r, sz := decode_rune_at(b, offset)
	if sz == 0 do return "", 0, 0, false

	target_class := get_char_class(r, big_word)

	start_idx := offset
	for start_idx > 0 {
		prev_r, prev_sz := decode_prev_rune(b, start_idx)
		if prev_sz == 0 do break
		if get_char_class(prev_r, big_word) != target_class {
			break
		}
		start_idx -= prev_sz
	}

	end_idx := offset + sz
	for end_idx < total_len {
		next_r, next_sz := decode_rune_at(b, end_idx)
		if next_sz == 0 do break
		if get_char_class(next_r, big_word) != target_class {
			break
		}
		end_idx += next_sz
	}

	line_idx, col_idx, ok_pos := offset_to_position(b, start_idx)
	if ok_pos {
		word_len := end_idx - start_idx
		word = string(b.lines[line_idx][col_idx:col_idx + word_len])
		return word, start_idx, target_class, true
	}

	return "", 0, 0, false
}
