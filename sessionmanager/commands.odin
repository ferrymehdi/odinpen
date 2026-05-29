package sessionmanager


import "../buffer"
import "../core/command"
import "../inputline"
import "../session"
import "../window"
import "core:fmt"

setup_commands :: proc(sm: ^session_manager) {
	command.register(
		&sm.cmd_binder,
		command.command {
			name = "quit",
			aliases = {"q"},
			callback = {proc(env: rawptr, args: []string) -> bool {
					m := (^session_manager)(env)
					return cmd_manager_quit(m, false)
				}, sm},
			description = "Quit the current window.",
		},
	)

	command.register(
		&sm.cmd_binder,
		command.command {
			name = "quit!",
			aliases = {"q!"},
			callback = {proc(env: rawptr, args: []string) -> bool {
					m := (^session_manager)(env)
					return cmd_manager_quit(m, true)
				}, sm},
			description = "Force quit the current window.",
		},
	)

	command.register(
		&sm.cmd_binder,
		command.command {
			name = "writequit",
			aliases = {"wq"},
			callback = {proc(env: rawptr, args: []string) -> bool {
					m := (^session_manager)(env)
					return cmd_manager_wq(m)
				}, sm},
			description = "Save and quit the current window.",
		},
	)
}

handle_command :: proc(m: ^session_manager, name: string, args: []string) -> bool {
	if command.execute(&m.cmd_binder, name, args) do return true

	s := get_active_session(m)
	if s != nil {
		return session.handle_command(s, name, args)
	}

	return false
}

cmd_manager_quit :: proc(m: ^session_manager, force: bool) -> bool {
	s := get_active_session(m)
	if s == nil {
		inputline.set_error("No active session")
		return false
	}

	if session.has_unsaved_buffers(s) && !force {
		inputline.set_error("Error: No write since last change (add ! to override)")
		return false
	}

	if m.session_on_close.call != nil {
		m.session_on_close.call(m.session_on_close.env, s)
	} else {
		close_active_session(m)
	}

	return true
}

cmd_manager_wq :: proc(m: ^session_manager) -> bool {
	s := get_active_session(m)
	if s == nil {
		inputline.set_error("No active session")
		return false
	}

	win := session.focused_window(s)
	if win != nil && win.buffer != nil {
		path := win.buffer.path
		if len(path) == 0 {
			inputline.set_error("Error: No file name")
			return false
		}
		if !buffer.save_to_file(win.buffer, path) {
			inputline.set_error(fmt.tprintf("Error: Can't open file for writing: %s", path))
			return false
		}
	}

	if m.session_on_close.call != nil {
		m.session_on_close.call(m.session_on_close.env, s)
	} else {
		close_active_session(m)
	}

	return true
}
