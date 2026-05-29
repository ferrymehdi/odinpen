package explorer

import "../core/keybind"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

file_entry :: struct {
	name:    string,
	is_dir:  bool,
	is_exec: bool,
}

explorer_modal_type :: enum {
	None,
	NewDir,
	NewFile,
	Rename,
	DeleteConfirm,
}

explorer_modal :: struct {
	type:        explorer_modal_type,
	input:       [dynamic]u8,
	cursor:      int,
	message:     string,
	target_path: string,
}

open_file_handler :: #type proc(env: rawptr, path: string) -> bool

Callback :: struct {
	call: open_file_handler,
	env:  rawptr,
}

file_explorer :: struct {
	current_dir:      string,
	entries:          [dynamic]file_entry,
	selected:         int,
	selections:       map[string]bool,
	modal:            explorer_modal,
	key_binder:       keybind.key_binder,
	modal_key_binder: keybind.key_binder,
	should_close:     bool,
	open_file_cb:     Callback,
}

init :: proc(fe: ^file_explorer, path: string, open_file_cb: Callback) -> bool {
	abs_path, ok := filepath.abs(path)
	if !ok {
		fe.current_dir = strings.clone(path)
	} else {
		fe.current_dir = abs_path
	}
	fe.entries = make([dynamic]file_entry)
	fe.selections = make(map[string]bool)
	fe.selected = 0
	fe.should_close = false
	fe.open_file_cb = open_file_cb

	fe.modal.type = .None
	fe.modal.input = make([dynamic]u8)
	fe.modal.cursor = 0
	fe.modal.message = ""
	fe.modal.target_path = ""

	keybind.init(&fe.key_binder)
	setup_keybinds(fe)

	keybind.init(&fe.modal_key_binder)
	setup_modal_keybinds(fe)

	return refresh(fe)
}

destroy :: proc(fe: ^file_explorer) {
	delete(fe.current_dir)
	clear_entries(fe)
	delete(fe.entries)

	clear_selections(fe)
	delete(fe.selections)

	if fe.modal.target_path != "" {
		delete(fe.modal.target_path)
	}
	delete(fe.modal.input)
	keybind.destroy(&fe.key_binder)
	keybind.destroy(&fe.modal_key_binder)
}

clear_entries :: proc(fe: ^file_explorer) {
	for e in fe.entries {
		delete(e.name)
	}
	clear(&fe.entries)
}

clear_selections :: proc(fe: ^file_explorer) {
	for path, _ in fe.selections {
		delete(path)
	}
	clear(&fe.selections)
}

refresh :: proc(fe: ^file_explorer) -> bool {
	f, err := os.open(fe.current_dir)
	if err != 0 do return false
	defer os.close(f)

	infos, err2 := os.read_dir(f, -1)
	if err2 != 0 do return false
	defer os.file_info_slice_delete(infos)

	clear_entries(fe)

	append(&fe.entries, file_entry{strings.clone(".."), true, false})

	for info in infos {
		is_exec := false
		append(&fe.entries, file_entry{strings.clone(info.name), info.is_dir, is_exec})
	}

	slice.sort_by(fe.entries[:], proc(a, b: file_entry) -> bool {
		if a.name == ".." do return true
		if b.name == ".." do return false
		if a.is_dir != b.is_dir do return a.is_dir
		return a.name < b.name
	})

	if fe.selected >= len(fe.entries) {
		fe.selected = max(0, len(fe.entries) - 1)
	}

	return true
}

open_modal :: proc(fe: ^file_explorer, type: explorer_modal_type, msg: string) {
	fe.modal.type = type
	fe.modal.message = msg
	clear(&fe.modal.input)
	fe.modal.cursor = 0
	if fe.modal.target_path != "" {
		delete(fe.modal.target_path)
		fe.modal.target_path = ""
	}
}

close_modal :: proc(fe: ^file_explorer) {
	fe.modal.type = .None
	clear(&fe.modal.input)
	fe.modal.cursor = 0
	if fe.modal.target_path != "" {
		delete(fe.modal.target_path)
		fe.modal.target_path = ""
	}
}

handle_modal_key :: proc(fe: ^file_explorer, key: keybind.key) -> bool {
	if fe.modal.type == .None do return false

	if keybind.handle(&fe.modal_key_binder, key) {
		return true
	}

	if fe.modal.type != .DeleteConfirm && key.char != 0 {
		buf, n := utf8.encode_rune(key.char)
		append(&fe.modal.input, ..buf[:n])
		fe.modal.cursor = len(fe.modal.input)
		return true
	}

	return true
}

remove_all :: proc(path: string) -> bool {
	f, err := os.open(path)
	if err != 0 {
		return os.remove(path) == 0
	}

	infos, err2 := os.read_dir(f, -1)
	if err2 != 0 {
		os.close(f)
		return os.remove(path) == 0
	}
	os.close(f)

	for info in infos {
		child_path, join_err := filepath.join({path, info.name})
		if join_err == nil {
			defer delete(child_path)
			remove_all(child_path)
		}
	}
	os.file_info_slice_delete(infos)

	return os.remove_directory(path) == 0
}

execute_deletion :: proc(fe: ^file_explorer) {
	num_selected := 0
	for _, selected in fe.selections {
		if selected do num_selected += 1
	}

	if num_selected > 0 {
		for path, selected in fe.selections {
			if selected {
				remove_all(path)
			}
		}
		clear_selections(fe)
	} else {
		if fe.selected >= 0 && fe.selected < len(fe.entries) {
			entry := fe.entries[fe.selected]
			if entry.name != ".." {
				path, err := filepath.join({fe.current_dir, entry.name})
				if err == nil {
					defer delete(path)
					remove_all(path)
				}
			}
		}
	}
	refresh(fe)
}

execute_new_dir :: proc(fe: ^file_explorer) {
	name := string(fe.modal.input[:])
	if len(name) == 0 do return

	path, err := filepath.join({fe.current_dir, name})
	if err == nil {
		defer delete(path)
		os.make_directory(path, 0o777)
	}
	refresh(fe)
}

execute_new_file :: proc(fe: ^file_explorer) {
	name := string(fe.modal.input[:])
	if len(name) == 0 do return

	path, err := filepath.join({fe.current_dir, name})
	if err == nil {
		defer delete(path)
		fd, err_open := os.open(path, os.O_CREATE | os.O_TRUNC | os.O_WRONLY, 0o666)
		if err_open == 0 {
			os.close(fd)
		}
	}
	refresh(fe)
}

execute_rename :: proc(fe: ^file_explorer) {
	if fe.modal.target_path == "" do return

	old_rel := fe.modal.target_path
	new_rel := string(fe.modal.input[:])

	old_path, err1 := filepath.join({fe.current_dir, old_rel})
	new_path, err2 := filepath.join({fe.current_dir, new_rel})

	if err1 == nil && err2 == nil {
		defer delete(old_path)
		defer delete(new_path)
		os.rename(old_path, new_path)
	}
	refresh(fe)
}
