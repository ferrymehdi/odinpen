package window

import "../buffer"
import "../core/command"
import "../inputline"
import "core:fmt"
import "core:os"

setup_commands :: proc(w: ^window) {
	command.register(
		&w.cmd_binder,
		command.command {
			name = "write",
			aliases = {"w"},
			callback = {cmd_write, w},
			description = "Save the window buffer to file.",
		},
	)
}

cmd_write :: proc(env: rawptr, args: []string) -> bool {
	w := (^window)(env)
	if w.buffer == nil do return false

	path := ""
	if len(args) > 0 {
		path = args[0]
	} else {
		path = w.buffer.path
	}

	if len(path) == 0 {
		inputline.set_error("Error: No file name")
		return false
	}

	is_new := !os.exists(path)
	ok := buffer.save_to_file(w.buffer, path)
	if ok {
		msg := fmt.tprintf(
			"\"%s\" %s%dL, %dB written",
			path,
			is_new ? "[New] " : "",
			buffer.line_count(w.buffer),
			buffer.len_bytes(w.buffer),
		)
		inputline.set_message(msg)
	} else {
		msg := fmt.tprintf("Error: Can't open file for writing: %s", path)
		inputline.set_error(msg)
	}
	return ok
}
