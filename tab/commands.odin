package tab

import "../core/command"

setup_commands :: proc(t: ^tab) {
	command.register(
		&t.cmd_binder,
		command.command {
			name = "vsplit",
			aliases = {"vs", "vsp"},
			callback = {cmd_vsplit, t},
			description = "Split the active window vertically.",
		},
	)

	command.register(
		&t.cmd_binder,
		command.command {
			name = "split",
			aliases = {"sp"},
			callback = {cmd_split, t},
			description = "Split the active window horizontally.",
		},
	)
}

cmd_vsplit :: proc(env: rawptr, args: []string) -> bool {
	t := (^tab)(env)
	split_focused_window(t, .Vertical)
	return true
}

cmd_split :: proc(env: rawptr, args: []string) -> bool {
	t := (^tab)(env)
	split_focused_window(t, .Horizontal)
	return true
}
