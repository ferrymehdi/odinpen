package command

import "core:strings"

handler :: proc(env: rawptr, args: []string) -> bool

Callback :: struct {
	call: handler,
	env:  rawptr,
}

command :: struct {
	name:        string,
	aliases:     []string,
	callback:    Callback,
	description: string,
}

command_binder :: struct {
	commands: [dynamic]command,
}

init :: proc(cb: ^command_binder) {
	cb.commands = make([dynamic]command, 0, 8)
}

destroy :: proc(cb: ^command_binder) {
	for cmd in cb.commands {
		if len(cmd.aliases) > 0 {
			delete(cmd.aliases)
		}
	}
	delete(cb.commands)
}

register :: proc(cb: ^command_binder, cmd: command) {
	c := cmd
	if len(cmd.aliases) > 0 {
		c.aliases = make([]string, len(cmd.aliases))
		copy(c.aliases, cmd.aliases)
	}
	append(&cb.commands, c)
}

execute :: proc(cb: ^command_binder, name: string, args: []string) -> bool {
	for cmd in cb.commands {
		if cmd.name == name {
			if cmd.callback.call != nil {
				return cmd.callback.call(cmd.callback.env, args)
			}
			return true
		}
		for alias in cmd.aliases {
			if alias == name {
				if cmd.callback.call != nil {
					return cmd.callback.call(cmd.callback.env, args)
				}
				return true
			}
		}
	}
	return false
}

parse_command_line :: proc(cmd_line: string) -> (string, []string) {
	trimmed := strings.trim_space(cmd_line)
	if len(trimmed) == 0 do return "", nil

	parts := strings.split(trimmed, " ", context.temp_allocator)
	if len(parts) == 0 do return "", nil

	name := parts[0]
	args := make([dynamic]string, context.temp_allocator)
	for i := 1; i < len(parts); i += 1 {
		arg := strings.trim_space(parts[i])
		if len(arg) > 0 {
			append(&args, arg)
		}
	}
	return name, args[:]
}
