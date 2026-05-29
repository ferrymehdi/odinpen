package sessionmanager

import "../core/command"
import "../core/keybind"
import "../finder"
import "../inputline"
import "../session"
import "core:fmt"

session_close_proc :: #type proc(env: rawptr, s: ^session.session)

Close_Callback :: struct {
	call: session_close_proc,
	env:  rawptr,
}

session_manager :: struct {
	sessions:             [dynamic]^session.session,
	active_session:       session.session_id,
	next_session_id:      session.session_id,
	session_finder:       ^finder.finder_state,
	session_selected_idx: int,
	session_on_close:     Close_Callback,
	key_binder:           keybind.key_binder,
	cmd_binder:           command.command_binder,
}

init :: proc(m: ^session_manager, on_close: Close_Callback) {
	m.sessions = make([dynamic]^session.session, 0, 4)
	m.next_session_id = 1
	m.session_finder = nil
	m.session_selected_idx = 0
	m.session_on_close = on_close
	inputline.init()

	keybind.init(&m.key_binder)
	setup_keybinds(m)
	command.init(&m.cmd_binder)
	setup_commands(m)
}

destroy :: proc(m: ^session_manager) {
	destroy_session_finder(m)
	for s in m.sessions {
		session.destroy(s)
		free(s)
	}
	delete(m.sessions)
	inputline.destroy()
	keybind.destroy(&m.key_binder)
	command.destroy(&m.cmd_binder)
}

destroy_session_finder :: proc(m: ^session_manager) {
	if m.session_finder != nil {
		finder.destroy(m.session_finder)
		free(m.session_finder)
		m.session_finder = nil
	}
}

select_session_callback :: proc(env: rawptr, selected_item: string) -> bool {
	m := (^session_manager)(env)
	for s in m.sessions {
		expected := fmt.tprintf("%s [%s]", s.name, s.path)
		if expected == selected_item {
			m.active_session = s.id
			break
		}
	}
	return true
}

new_session :: proc(m: ^session_manager, name: string, path: string = ".") -> ^session.session {
	s := session.init(m.next_session_id, name, path)
	m.next_session_id += 1

	append(&m.sessions, s)

	if len(m.sessions) == 1 {
		m.active_session = s.id
	}

	return s
}

handle_key :: proc(
	m: ^session_manager,
	key: keybind.key,
) -> (
	handled: bool,
	process_session: bool,
) {
	if m.session_finder != nil {
		if key.code == keybind.KEY_ESCAPE || (key.code == 's' && key.mods == {.Alt}) {
			destroy_session_finder(m)
			return true, false
		}
		ret := finder.handle_key(m.session_finder, key)
		if m.session_finder.should_close {
			destroy_session_finder(m)
		}
		return true, false
	}

	if keybind.handle(&m.key_binder, key) {
		return true, false
	}

	return false, true
}

get_active_session :: proc(m: ^session_manager) -> ^session.session {
	for s in m.sessions {
		if s.id == m.active_session {
			return s
		}
	}
	return nil
}

close_active_session :: proc(m: ^session_manager) {
	idx := -1
	for s, i in m.sessions {
		if s.id == m.active_session {
			idx = i
			break
		}
	}
	if idx != -1 {
		s := m.sessions[idx]
		session.destroy(s)
		free(s)
		ordered_remove(&m.sessions, idx)
		if len(m.sessions) > 0 {
			m.active_session = m.sessions[max(0, idx - 1)].id
		}
	}
}
