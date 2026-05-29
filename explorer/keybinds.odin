package explorer

import "../core/keybind"
import "core:fmt"
import "core:mem"
import "core:path/filepath"
import "core:strings"
import "core:unicode/utf8"

setup_keybinds :: proc(fe: ^file_explorer) {
	keybind.bind_single(&fe.key_binder, {char = '-'}, {go_up, fe})
	keybind.bind_single(&fe.key_binder, {code = keybind.KEY_ENTER}, {activate, fe})
	keybind.bind_single(&fe.key_binder, {char = 'j'}, {move_down, fe})
	keybind.bind_single(&fe.key_binder, {code = keybind.KEY_DOWN}, {move_down, fe})
	keybind.bind_single(&fe.key_binder, {char = 'k'}, {move_up, fe})
	keybind.bind_single(&fe.key_binder, {code = keybind.KEY_UP}, {move_up, fe})
	keybind.bind_single(&fe.key_binder, {char = 'h'}, {go_up, fe})
	keybind.bind_single(&fe.key_binder, {char = 'l'}, {activate, fe})
	keybind.bind_single(&fe.key_binder, {char = ' '}, {select, fe})
	keybind.bind_single(&fe.key_binder, {char = 'c'}, {clear_selection, fe})
	keybind.bind_single(&fe.key_binder, {char = 'd'}, {delete_prompt, fe})
	keybind.bind_single(&fe.key_binder, {char = 'r'}, {rename_prompt, fe})
	keybind.bind_keys(
		&fe.key_binder,
		[]keybind.key{{char = 'n'}, {char = 'd'}},
		{new_dir_prompt, fe},
	)
	keybind.bind_keys(
		&fe.key_binder,
		[]keybind.key{{char = 'n'}, {char = 'f'}},
		{new_file_prompt, fe},
	)
}

go_up :: proc(env: rawptr) -> bool {
	fe := (^file_explorer)(env)
	new_path, err := filepath.join({fe.current_dir, ".."})
	if err == nil {
		delete(fe.current_dir)
		fe.current_dir = new_path
		fe.selected = 0
		refresh(fe)
	}
	return true
}

activate :: proc(env: rawptr) -> bool {
	fe := (^file_explorer)(env)
	if fe.selected >= 0 && fe.selected < len(fe.entries) {
		entry := fe.entries[fe.selected]
		if entry.is_dir {
			new_path: string
			err: mem.Allocator_Error
			if entry.name == ".." {
				new_path, err = filepath.join({fe.current_dir, ".."})
			} else {
				new_path, err = filepath.join({fe.current_dir, entry.name})
			}
			if err == nil {
				delete(fe.current_dir)
				fe.current_dir = new_path
				fe.selected = 0
				refresh(fe)
			}
		} else {
			file_path, err := filepath.join({fe.current_dir, entry.name})
			if err == nil {
				if fe.open_file_cb.call != nil &&
				   fe.open_file_cb.call(fe.open_file_cb.env, file_path) {
					fe.should_close = true
				}
				delete(file_path)
			}
		}
	}
	return true
}

move_up :: proc(env: rawptr) -> bool {
	fe := (^file_explorer)(env)
	if fe.selected > 0 {
		fe.selected -= 1
	}
	return true
}

move_down :: proc(env: rawptr) -> bool {
	fe := (^file_explorer)(env)
	if fe.selected < len(fe.entries) - 1 {
		fe.selected += 1
	}
	return true
}

select :: proc(env: rawptr) -> bool {
	fe := (^file_explorer)(env)
	if fe.selected >= 0 && fe.selected < len(fe.entries) {
		entry := fe.entries[fe.selected]
		if entry.name != ".." {
			path, err := filepath.join({fe.current_dir, entry.name})
			if err == nil {
				if path in fe.selections {
					for k, _ in fe.selections {
						if k == path {
							delete_key(&fe.selections, k)
							delete(k)
							break
						}
					}
					delete(path)
				} else {
					fe.selections[path] = true
				}
			}
		}
	}
	return true
}

clear_selection :: proc(env: rawptr) -> bool {
	fe := (^file_explorer)(env)
	clear_selections(fe)
	return true
}

delete_prompt :: proc(env: rawptr) -> bool {
	fe := (^file_explorer)(env)
	num_selected := 0
	for _, selected in fe.selections {
		if selected do num_selected += 1
	}

	if num_selected > 0 {
		msg := fmt.tprintf("Delete %d selected items? (y/n)", num_selected)
		open_modal(fe, .DeleteConfirm, msg)
	} else {
		if fe.selected >= 0 && fe.selected < len(fe.entries) {
			entry := fe.entries[fe.selected]
			if entry.name != ".." {
				msg := fmt.tprintf("Delete '%s'? (y/n)", entry.name)
				open_modal(fe, .DeleteConfirm, msg)
			}
		}
	}
	return true
}

rename_prompt :: proc(env: rawptr) -> bool {
	fe := (^file_explorer)(env)
	if fe.selected >= 0 && fe.selected < len(fe.entries) {
		entry := fe.entries[fe.selected]
		if entry.name != ".." {
			open_modal(fe, .Rename, "Rename to:")
			clear(&fe.modal.input)
			append(&fe.modal.input, ..transmute([]u8)entry.name)
			fe.modal.cursor = len(fe.modal.input)
			fe.modal.target_path = strings.clone(entry.name)
		}
	}
	return true
}

new_dir_prompt :: proc(env: rawptr) -> bool {
	fe := (^file_explorer)(env)
	open_modal(fe, .NewDir, "New Directory Name:")
	return true
}

new_file_prompt :: proc(env: rawptr) -> bool {
	fe := (^file_explorer)(env)
	open_modal(fe, .NewFile, "New File Name:")
	return true
}

setup_modal_keybinds :: proc(fe: ^file_explorer) {
	keybind.bind_single(&fe.modal_key_binder, {code = keybind.KEY_ESCAPE}, {close_modal_cmd, fe})
	keybind.bind_single(&fe.modal_key_binder, {code = keybind.KEY_ENTER}, {modal_enter_cmd, fe})
	keybind.bind_single(
		&fe.modal_key_binder,
		{code = keybind.KEY_BACKSPACE},
		{modal_backspace_cmd, fe},
	)
	keybind.bind_single(&fe.modal_key_binder, {char = 'y'}, {modal_delete_y_cmd, fe})
	keybind.bind_single(&fe.modal_key_binder, {char = 'n'}, {modal_delete_n_cmd, fe})
}

close_modal_cmd :: proc(env: rawptr) -> bool {
	fe := (^file_explorer)(env)
	close_modal(fe)
	return true
}

modal_enter_cmd :: proc(env: rawptr) -> bool {
	fe := (^file_explorer)(env)
	if fe.modal.type == .DeleteConfirm {
		execute_deletion(fe)
	} else {
		#partial switch fe.modal.type {
		case .NewDir:
			execute_new_dir(fe)
		case .NewFile:
			execute_new_file(fe)
		case .Rename:
			execute_rename(fe)
		}
	}
	close_modal(fe)
	return true
}

modal_backspace_cmd :: proc(env: rawptr) -> bool {
	fe := (^file_explorer)(env)
	if fe.modal.type != .DeleteConfirm {
		if len(fe.modal.input) > 0 {
			str := string(fe.modal.input[:])
			_, size := utf8.decode_last_rune_in_string(str)
			if size > 0 {
				resize(&fe.modal.input, len(fe.modal.input) - size)
				fe.modal.cursor = len(fe.modal.input)
			}
		}
	}
	return true
}

modal_delete_y_cmd :: proc(env: rawptr) -> bool {
	fe := (^file_explorer)(env)
	if fe.modal.type == .DeleteConfirm {
		execute_deletion(fe)
		close_modal(fe)
		return true
	}
	return false
}

modal_delete_n_cmd :: proc(env: rawptr) -> bool {
	fe := (^file_explorer)(env)
	if fe.modal.type == .DeleteConfirm {
		close_modal(fe)
		return true
	}
	return false
}
