package keybind

None :: 0

KEY_SPACE :: 32

KEY_ESCAPE :: 256

KEY_ENTER :: 257

KEY_TAB :: 258

KEY_BACKSPACE :: 259

KEY_INSERT :: 260

KEY_DELETE :: 261

KEY_RIGHT :: 262

KEY_LEFT :: 263

KEY_DOWN :: 264

KEY_UP :: 265

modifier :: enum {
	Shift,
	Control,
	Alt,
}

modifiers :: bit_set[modifier]

key :: struct {
	code: i32,
	mods: modifiers,
	char: rune,
}

handler :: proc(env: rawptr) -> bool

Callback :: struct {
	call: handler,
	env:  rawptr,
}

key_binding :: struct {
	keys:    [dynamic]key,
	handler: Callback,
}

key_binder :: struct {
	bindings: [dynamic]key_binding,
	sequence: [dynamic]key,
}

init :: proc(kb: ^key_binder) {
	kb.bindings = make([dynamic]key_binding, 0, 8)
	kb.sequence = make([dynamic]key, 0, 4)
}

destroy :: proc(kb: ^key_binder) {
	for b in kb.bindings {
		delete(b.keys)
	}
	delete(kb.bindings)
	delete(kb.sequence)
}

bind_keys :: proc(kb: ^key_binder, keys: []key, cb: Callback) {
	b_keys := make([dynamic]key, 0, len(keys))
	append(&b_keys, ..keys)
	append(&kb.bindings, key_binding{b_keys, cb})
}

bind_single :: proc(kb: ^key_binder, k: key, cb: Callback) {
	bind_keys(kb, []key{k}, cb)
}

matches_key :: proc(a, b: key) -> bool {
	if a.code != 0 && b.code != 0 {
		return a.code == b.code && a.mods == b.mods
	} else if a.char != 0 && b.char != 0 {
		a_mods := a.mods - {.Shift}
		b_mods := b.mods - {.Shift}
		return a.char == b.char && a_mods == b_mods
	}
	return false
}

matches_sequence :: proc(binding_seq, input_seq: []key) -> bool {
	if len(binding_seq) != len(input_seq) do return false
	for i in 0 ..< len(binding_seq) {
		if !matches_key(binding_seq[i], input_seq[i]) do return false
	}
	return true
}

is_prefix_of :: proc(prefix, full: []key) -> bool {
	if len(prefix) > len(full) do return false
	for i in 0 ..< len(prefix) {
		if !matches_key(prefix[i], full[i]) do return false
	}
	return true
}

match_status :: enum {
	None,
	Partial,
	Complete,
}

check_sequence_match :: proc(kb: ^key_binder, input_seq: []key) -> match_status {
	has_partial := false
	for b in kb.bindings {
		if matches_sequence(b.keys[:], input_seq) {
			return .Complete
		}
		if len(b.keys) > len(input_seq) {
			if is_prefix_of(input_seq, b.keys[:]) {
				has_partial = true
			}
		}
	}
	return has_partial ? .Partial : .None
}

handle :: proc(kb: ^key_binder, key: key) -> bool {
	append(&kb.sequence, key)

	status := check_sequence_match(kb, kb.sequence[:])
	if status == .Complete {
		for b in kb.bindings {
			if matches_sequence(b.keys[:], kb.sequence[:]) {
				clear(&kb.sequence)
				if b.handler.call != nil {
					return b.handler.call(b.handler.env)
				}
				return true
			}
		}
	} else if status == .Partial {
		return true
	} else {
		if len(kb.sequence) > 1 {
			last_key := kb.sequence[len(kb.sequence) - 1]
			clear(&kb.sequence)
			append(&kb.sequence, last_key)
			status_new := check_sequence_match(kb, kb.sequence[:])
			if status_new == .Complete {
				for b in kb.bindings {
					if matches_sequence(b.keys[:], kb.sequence[:]) {
						clear(&kb.sequence)
						if b.handler.call != nil {
							return b.handler.call(b.handler.env)
						}
						return true
					}
				}
			} else if status_new == .Partial {
				return true
			}
		}
		clear(&kb.sequence)
		return false
	}
	return false
}
