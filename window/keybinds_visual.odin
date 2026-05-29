package window

import "../core/keybind"

setup_visual_keybinds :: proc(w: ^window) {
	keybind.bind_single(&w.visual_kb, {code = keybind.KEY_ESCAPE}, {proc(env: rawptr) -> bool {
			w := (^window)(env)
			w.mode = .Normal
			return true
		}, w})
}
