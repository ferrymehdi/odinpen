package finder

import "../core/keybind"
import "core:slice"
import "core:strings"
import "core:unicode"

finder_match :: struct {
	item:  string,
	score: int,
}

select_handler :: proc(env: rawptr, item: string) -> bool

Callback :: struct {
	call: select_handler,
	env:  rawptr,
}

finder_state :: struct {
	all_items:    [dynamic]string,
	filtered:     [dynamic]finder_match,
	selected:     int,
	input:        [dynamic]u8,
	cursor:       int,
	should_close: bool,
	on_select:    Callback,
	key_binder:   keybind.key_binder,
}

init :: proc(ff: ^finder_state, items: []string, on_select: Callback) {
	ff.all_items = make([dynamic]string)
	ff.filtered = make([dynamic]finder_match)
	ff.input = make([dynamic]u8)
	ff.cursor = 0
	ff.selected = 0
	ff.should_close = false
	ff.on_select = on_select

	keybind.init(&ff.key_binder)
	setup_keybinds(ff)

	for item in items {
		append(&ff.all_items, strings.clone(item))
	}
	update_filter(ff)
}

destroy :: proc(ff: ^finder_state) {
	for item in ff.all_items {
		delete(item)
	}
	delete(ff.all_items)
	delete(ff.filtered)
	delete(ff.input)
	keybind.destroy(&ff.key_binder)
}

fuzzy_match :: proc(pattern, target: string) -> (int, bool) {
	if len(pattern) == 0 do return 0, true

	p_runes := make([dynamic]rune, 0, len(pattern), context.temp_allocator)
	for r in pattern {
		append(&p_runes, unicode.to_lower(r))
	}

	t_runes := make([dynamic]rune, 0, len(target), context.temp_allocator)
	for r in target {
		append(&t_runes, unicode.to_lower(r))
	}

	p_idx := 0
	score := 0
	last_match_idx := -1

	for t_idx := 0; t_idx < len(t_runes); t_idx += 1 {
		if p_idx < len(p_runes) && t_runes[t_idx] == p_runes[p_idx] {
			if last_match_idx != -1 {
				dist := t_idx - last_match_idx
				if dist == 1 {
					score += 10
				} else {
					score += max(0, 5 - dist)
				}
			}
			if t_idx == 0 ||
			   t_runes[t_idx - 1] == '/' ||
			   t_runes[t_idx - 1] == '_' ||
			   t_runes[t_idx - 1] == '.' {
				score += 8
			}
			last_match_idx = t_idx
			p_idx += 1
		}
	}

	matched := p_idx == len(p_runes)
	return score, matched
}

update_filter :: proc(ff: ^finder_state) {
	clear(&ff.filtered)
	query := string(ff.input[:])

	for item in ff.all_items {
		score, matched := fuzzy_match(query, item)
		if matched {
			append(&ff.filtered, finder_match{item, score})
		}
	}

	slice.sort_by(ff.filtered[:], proc(a, b: finder_match) -> bool {
		if a.score != b.score {
			return a.score > b.score
		}
		return len(a.item) < len(b.item)
	})

	if ff.selected >= len(ff.filtered) {
		ff.selected = max(0, len(ff.filtered) - 1)
	}
}
