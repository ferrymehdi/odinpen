package tab

import "../core/keybind"

setup_keybinds :: proc(t: ^tab) {
	keybind.bind_keys(
		&t.key_binder,
		[]keybind.key{{code = 'w', mods = {.Control}}, {char = 'v'}},
		{call = kb_split_v, env = t},
	)

	keybind.bind_keys(
		&t.key_binder,
		[]keybind.key{{code = 'w', mods = {.Control}}, {char = 's'}},
		{call = kb_split_h, env = t},
	)

	keybind.bind_keys(
		&t.key_binder,
		[]keybind.key{{code = 'w', mods = {.Control}}, {char = 'h'}},
		{call = kb_focus_l, env = t},
	)

	keybind.bind_keys(
		&t.key_binder,
		[]keybind.key{{code = 'w', mods = {.Control}}, {char = 'j'}},
		{call = kb_focus_d, env = t},
	)

	keybind.bind_keys(
		&t.key_binder,
		[]keybind.key{{code = 'w', mods = {.Control}}, {char = 'k'}},
		{call = kb_focus_u, env = t},
	)

	keybind.bind_keys(
		&t.key_binder,
		[]keybind.key{{code = 'w', mods = {.Control}}, {char = 'l'}},
		{call = kb_focus_r, env = t},
	)

	keybind.bind_keys(
		&t.key_binder,
		[]keybind.key{{code = 'w', mods = {.Control}}, {char = 'w'}},
		{call = kb_cycle, env = t},
	)

	keybind.bind_keys(
		&t.key_binder,
		[]keybind.key{{code = 'w', mods = {.Control}}, {char = 'c'}},
		{call = kb_close, env = t},
	)

	keybind.bind_single(
		&t.key_binder,
		keybind.key{code = 'h', mods = {.Control}},
		{call = kb_focus_l, env = t},
	)

	keybind.bind_single(
		&t.key_binder,
		keybind.key{code = 'j', mods = {.Control}},
		{call = kb_focus_d, env = t},
	)

	keybind.bind_single(
		&t.key_binder,
		keybind.key{code = 'k', mods = {.Control}},
		{call = kb_focus_u, env = t},
	)

	keybind.bind_single(
		&t.key_binder,
		keybind.key{code = 'l', mods = {.Control}},
		{call = kb_focus_r, env = t},
	)
}

kb_split_v :: proc(env: rawptr) -> bool {
	t := (^tab)(env)
	split_focused_window(t, .Vertical)
	return true
}

kb_split_h :: proc(env: rawptr) -> bool {
	t := (^tab)(env)
	split_focused_window(t, .Horizontal)
	return true
}

kb_focus_l :: proc(env: rawptr) -> bool {
	t := (^tab)(env)
	focus_window_in_direction(t, .Left)
	return true
}

kb_focus_d :: proc(env: rawptr) -> bool {
	t := (^tab)(env)
	focus_window_in_direction(t, .Down)
	return true
}

kb_focus_u :: proc(env: rawptr) -> bool {
	t := (^tab)(env)
	focus_window_in_direction(t, .Up)
	return true
}

kb_focus_r :: proc(env: rawptr) -> bool {
	t := (^tab)(env)
	focus_window_in_direction(t, .Right)
	return true
}

kb_cycle :: proc(env: rawptr) -> bool {
	t := (^tab)(env)
	cycle_focused_window(t)
	return true
}

kb_close :: proc(env: rawptr) -> bool {
	t := (^tab)(env)
	close_focused_window(t)
	return true
}
