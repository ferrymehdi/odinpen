package session

import "../buffer"
import "../core/command"
import "../core/keybind"
import "../inputline"
import "../tab"
import "../window"
import "core:strings"

session_id :: distinct int

session :: struct {
	id:         session_id,
	name:       string,
	path:       string,
	tabs:       [dynamic]^tab.tab,
	buffers:    [dynamic]^buffer.buffer,
	active_tab: int,
	keybinder:  keybind.key_binder,
	cmd_binder: command.command_binder,
}

init :: proc(id: session_id, name: string, path: string) -> ^session {
	s := new(session)
	s.id = id
	s.name = strings.clone(name)
	s.path = strings.clone(path)
	s.tabs = make([dynamic]^tab.tab, 0, 4)
	s.buffers = make([dynamic]^buffer.buffer, 0, 4)
	s.active_tab = 0

	keybind.init(&s.keybinder)
	command.init(&s.cmd_binder)
	setup_commands(s)

	default_buf := new(buffer.buffer)
	buffer.init(default_buf)
	append(&s.buffers, default_buf)

	t := tab.init(1, "tab 1", default_buf, &s.buffers, {is_buffer_open_elsewhere, s})
	add_tab(s, t)

	return s
}

destroy :: proc(s: ^session) {
	for t in s.tabs {
		tab.destroy(t)
		free(t)
	}
	delete(s.tabs)
	for b in s.buffers {
		buffer.destroy(b)
		free(b)
	}
	delete(s.buffers)
	delete(s.name)
	delete(s.path)
	keybind.destroy(&s.keybinder)
	command.destroy(&s.cmd_binder)
}

is_buffer_open_elsewhere :: proc(
	env: rawptr,
	b: ^buffer.buffer,
	excluding_win: ^window.window,
) -> bool {
	s := (^session)(env)
	for t in s.tabs {
		for w in t.windows {
			if w != excluding_win && w.buffer == b {
				return true
			}
		}
	}
	return false
}

is_buffer_open_in_other_tabs :: proc(
	s: ^session,
	excluding_tab: ^tab.tab,
	b: ^buffer.buffer,
) -> bool {
	for t in s.tabs {
		if t == excluding_tab do continue
		for w in t.windows {
			if w.buffer == b {
				return true
			}
		}
	}
	return false
}

tab_on_close :: proc(s: ^session, t: ^tab.tab, force: bool) -> bool {
	if len(s.tabs) > 1 {
		idx := -1
		for curr, i in s.tabs {
			if curr == t {
				idx = i
				break
			}
		}
		if idx != -1 {
			if !force {
				for w in t.windows {
					if w.buffer != nil && .Is_Updated in w.buffer.flags {
						if !is_buffer_open_in_other_tabs(s, t, w.buffer) {
							inputline.set_error(
								"Error: No write since last change (add ! to override)",
							)
							return false
						}
					}
				}
			}
			tab.destroy(t)
			free(t)
			ordered_remove(&s.tabs, idx)
			if s.active_tab >= len(s.tabs) {
				s.active_tab = len(s.tabs) - 1
			}
			return true
		}
	}
	return false
}

focused_window :: proc(s: ^session) -> ^window.window {
	t := focused_tab(s)
	if t == nil do return nil
	return tab.focused_window(t)
}

preview_handle_key :: proc(s: ^session, key: keybind.key) -> (bool, string) {
	return false, ""
}

handle_key :: proc(s: ^session, key: keybind.key) -> bool {
	if keybind.handle(&s.keybinder, key) {
		return true
	}

	return false
}

handle_command :: proc(s: ^session, name: string, args: []string) -> bool {
	if command.execute(&s.cmd_binder, name, args) do return true

	t := focused_tab(s)
	if t != nil {
		return tab.handle_command(t, name, args)
	}

	return false
}

add_tab :: proc(s: ^session, t: ^tab.tab) {
	append(&s.tabs, t)
	if len(s.tabs) == 1 {
		s.active_tab = 0
	}
}

focused_tab :: proc(s: ^session) -> ^tab.tab {
	if s.active_tab >= 0 && s.active_tab < len(s.tabs) {
		return s.tabs[s.active_tab]
	}
	return nil
}

tab_count :: proc(s: ^session) -> int {
	return len(s.tabs)
}

get_active_mode :: proc(s: ^session) -> window.mode {
	active_tab := focused_tab(s)
	if active_tab != nil {
		return tab.get_focused_window_mode(active_tab)
	}
	return .Normal
}

get_active_font_size :: proc(s: ^session) -> f32 {
	active_tab := focused_tab(s)
	if active_tab != nil {
		return tab.get_focused_window_font_size(active_tab)
	}
	return 18.0
}

has_unsaved_buffers :: proc(s: ^session) -> bool {
	for b in s.buffers {
		if .Is_Updated in b.flags {
			return true
		}
	}
	return false
}

close_tab :: proc(s: ^session, force: bool) -> (bool, bool) {
	t := focused_tab(s)
	if t == nil do return false, false

	ok, closed_split := tab.close_window(t, force)
	if !ok do return false, false
	if closed_split do return true, true

	if len(s.tabs) > 1 {
		return tab_on_close(s, t, force), true
	}

	return true, false
}
