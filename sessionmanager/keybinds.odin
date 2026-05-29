package sessionmanager


import "../core/keybind"
import "../finder"
import "../session"
import "core:fmt"

setup_keybinds :: proc(m: ^session_manager) {
	keybind.bind_single(&m.key_binder, {code = 'c', mods = {.Alt}}, {create_new_session, m})
	keybind.bind_single(&m.key_binder, {code = 's', mods = {.Alt}}, {toggle_session_finder, m})
}

create_new_session :: proc(env: rawptr) -> bool {
	m := (^session_manager)(env)
	SESSION_NAMES := []string {
		"session 1",
		"session 2",
		"session 3",
		"session 4",
		"session 5",
		"session 6",
		"session 7",
		"session 8",
		"session 9",
		"session 10",
		"session 11",
		"session 12",
	}
	name := "session"
	idx := int(m.next_session_id) - 1
	if idx >= 0 && idx < len(SESSION_NAMES) {
		name = SESSION_NAMES[idx]
	} else {
		name = fmt.tprintf("session %d", int(m.next_session_id))
	}

	s := new_session(m, name, ".")
	m.active_session = s.id
	return true
}

toggle_session_finder :: proc(env: rawptr) -> bool {
	m := (^session_manager)(env)
	if m.session_finder != nil {
		destroy_session_finder(m)
	} else {
		items := make([dynamic]string, context.temp_allocator)
		for s in m.sessions {
			append(&items, fmt.tprintf("%s [%s]", s.name, s.path))
		}
		m.session_finder = new(finder.finder_state)
		finder.init(m.session_finder, items[:], {select_session_callback, m})
	}
	return true
}
