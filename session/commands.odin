package session

import "../buffer"
import "../core/command"
import "../tab"
import "../window"
import "core:fmt"
import "core:path/filepath"
import "core:strings"

setup_commands :: proc(s: ^session) {
	command.register(
		&s.cmd_binder,
		command.command {
			name = "edit",
			aliases = {"e"},
			callback = {cmd_edit, s},
			description = "Open/edit a file in the active window.",
		},
	)

	command.register(
		&s.cmd_binder,
		command.command {
			name = "tabnew",
			aliases = {"tabe", "tabedit"},
			callback = {cmd_tabnew, s},
			description = "Create a new tab, optionally opening a file.",
		},
	)

	command.register(
		&s.cmd_binder,
		command.command {
			name = "tabnext",
			aliases = {"tabn"},
			callback = {cmd_tabnext, s},
			description = "Go to the next tab.",
		},
	)

	command.register(
		&s.cmd_binder,
		command.command {
			name = "tabprevious",
			aliases = {"tabp", "tabprev"},
			callback = {cmd_tabprev, s},
			description = "Go to the previous tab.",
		},
	)

	command.register(
		&s.cmd_binder,
		command.command {
			name = "tabclose",
			aliases = {"tabc"},
			callback = {cmd_tabclose, s},
			description = "Close the current tab.",
		},
	)
}

cmd_tabnew :: proc(env: rawptr, args: []string) -> bool {
	s := (^session)(env)

	new_tab_idx := len(s.tabs) + 1
	name_buf: string
	if len(args) > 0 {
		name_buf = filepath.base(args[0])
	} else {
		name_buf = fmt.tprintf("tab %d", new_tab_idx)
	}

	buf: ^buffer.buffer = nil
	if len(args) > 0 {
		for b in s.buffers {
			if b.path == args[0] {
				buf = b
				break
			}
		}
		if buf == nil {
			buf = new(buffer.buffer)
			buffer.init(buf)
			if buffer.load_from_file(buf, args[0]) {
				append(&s.buffers, buf)
			} else {
				buffer.destroy(buf)
				free(buf)
				buf = nil
			}
		}
	}

	if buf == nil {
		buf = new(buffer.buffer)
		buffer.init(buf)
		append(&s.buffers, buf)
	}

	t := tab.init(
		tab.tab_id(new_tab_idx),
		name_buf,
		buf,
		&s.buffers,
		{is_buffer_open_elsewhere, s},
	)
	add_tab(s, t)

	s.active_tab = len(s.tabs) - 1
	return true
}

cmd_edit :: proc(env: rawptr, args: []string) -> bool {
	s := (^session)(env)
	if len(args) == 0 do return false

	win := focused_window(s)
	if win == nil do return false

	path := args[0]
	if !window.open_file(win, path) do return false

	t := focused_tab(s)
	if t != nil && win.buffer != nil {
		delete(t.name)
		t.name = strings.clone(filepath.base(win.buffer.path))
	}

	return true
}

cmd_tabnext :: proc(env: rawptr, args: []string) -> bool {
	s := (^session)(env)
	if len(s.tabs) <= 1 do return true
	s.active_tab = (s.active_tab + 1) % len(s.tabs)
	return true
}

cmd_tabprev :: proc(env: rawptr, args: []string) -> bool {
	s := (^session)(env)
	if len(s.tabs) <= 1 do return true
	s.active_tab = (s.active_tab - 1 + len(s.tabs)) % len(s.tabs)
	return true
}

cmd_tabclose :: proc(env: rawptr, args: []string) -> bool {
	s := (^session)(env)
	if len(s.tabs) <= 1 do return false

	t := s.tabs[s.active_tab]
	return tab_on_close(s, t, false)
}
