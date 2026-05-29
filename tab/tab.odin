package tab

import "../buffer"
import "../core/command"
import "../core/keybind"
import "../inputline"
import "../window"
import "core:strings"

tab_id :: distinct int

split_direction :: enum {
	Vertical,
	Horizontal,
}

navigation_direction :: enum {
	Left,
	Right,
	Up,
	Down,
}

Layout_Node :: struct {
	is_split: bool,
	dir:      split_direction,
	window:   ^window.window,
	children: [dynamic]^Layout_Node,
}

buffer_open_handler :: #type proc(
	env: rawptr,
	buf: ^buffer.buffer,
	ignore_win: ^window.window,
) -> bool

Buffer_Open_Callback :: struct {
	call: buffer_open_handler,
	env:  rawptr,
}

tab :: struct {
	id:                       tab_id,
	name:                     string,
	windows:                  [dynamic]^window.window,
	focused_window:           int,
	key_binder:               keybind.key_binder,
	cmd_binder:               command.command_binder,
	layout:                   ^Layout_Node,
	buffers:                  ^[dynamic]^buffer.buffer,
	is_buffer_open_elsewhere: Buffer_Open_Callback,
}

init :: proc(
	id: tab_id,
	name: string,
	default_buf: ^buffer.buffer,
	buffers: ^[dynamic]^buffer.buffer,
	is_buffer_open_elsewhere: Buffer_Open_Callback,
) -> ^tab {
	t := new(tab)
	t.id = id
	t.name = strings.clone(name)
	t.windows = make([dynamic]^window.window, 0, 4)
	t.focused_window = 0
	t.buffers = buffers
	t.is_buffer_open_elsewhere = is_buffer_open_elsewhere

	keybind.init(&t.key_binder)
	command.init(&t.cmd_binder)
	setup_keybinds(t)
	setup_commands(t)

	w := window.init(1, default_buf, buffers)
	add_window(t, w)

	t.layout = new(Layout_Node)
	t.layout.is_split = false
	t.layout.window = w
	t.layout.children = make([dynamic]^Layout_Node, 0, 4)

	return t
}

destroy :: proc(t: ^tab) {
	for w in t.windows {
		window.destroy(w)
		free(w)
	}
	delete(t.windows)
	keybind.destroy(&t.key_binder)
	command.destroy(&t.cmd_binder)
	free_layout(t.layout)
	delete(t.name)
}

free_layout :: proc(node: ^Layout_Node) {
	if node == nil do return
	for child in node.children {
		free_layout(child)
	}
	delete(node.children)
	free(node)
}

find_leaf_node :: proc(node: ^Layout_Node, w: ^window.window) -> ^Layout_Node {
	if node == nil do return nil
	if !node.is_split {
		if node.window == w do return node
		return nil
	}
	for child in node.children {
		res := find_leaf_node(child, w)
		if res != nil do return res
	}
	return nil
}

find_parent_node :: proc(
	parent, current: ^Layout_Node,
	target_win: ^window.window,
) -> (
	^Layout_Node,
	int,
) {
	if current == nil do return nil, -1
	if !current.is_split do return nil, -1

	for child, idx in current.children {
		if !child.is_split && child.window == target_win {
			return current, idx
		}
		p, i := find_parent_node(current, child, target_win)
		if p != nil do return p, i
	}
	return nil, -1
}

split_focused_window :: proc(t: ^tab, dir: split_direction) {
	curr_win := focused_window(t)
	if curr_win == nil do return

	leaf := find_leaf_node(t.layout, curr_win)
	if leaf == nil do return

	new_win := window.clone(curr_win, window.window_id(len(t.windows) + 1))

	append(&t.windows, new_win)

	leaf.is_split = true
	leaf.dir = dir
	leaf.window = nil

	child1 := new(Layout_Node)
	child1.is_split = false
	child1.window = curr_win
	child1.children = make([dynamic]^Layout_Node, 0, 4)

	child2 := new(Layout_Node)
	child2.is_split = false
	child2.window = new_win
	child2.children = make([dynamic]^Layout_Node, 0, 4)

	append(&leaf.children, child1, child2)

	t.focused_window = len(t.windows) - 1
	update_active_window(t)
}

close_focused_window :: proc(t: ^tab) {
	if len(t.windows) <= 1 do return

	curr_win := focused_window(t)
	if curr_win == nil do return

	parent, idx := find_parent_node(nil, t.layout, curr_win)
	if parent == nil do return

	sibling_idx := 1 - idx
	sibling := parent.children[sibling_idx]

	old_children := parent.children
	parent.is_split = sibling.is_split
	parent.dir = sibling.dir
	parent.window = sibling.window
	parent.children = sibling.children

	closed_node := old_children[idx]
	delete(closed_node.children)
	free(closed_node)
	free(sibling)
	delete(old_children)

	win_idx := -1
	for w, i in t.windows {
		if w == curr_win {
			win_idx = i
			break
		}
	}
	if win_idx != -1 {
		window.destroy(curr_win)
		free(curr_win)
		ordered_remove(&t.windows, win_idx)
	}

	t.focused_window = max(0, t.focused_window - 1)
	if t.focused_window >= len(t.windows) {
		t.focused_window = len(t.windows) - 1
	}
	update_active_window(t)
}

focus_window_in_direction :: proc(t: ^tab, dir: navigation_direction) {
	curr_win := focused_window(t)
	if curr_win == nil do return

	curr_pos := window.get_position(curr_win)
	curr_sz := window.get_size(curr_win)

	curr_center := [2]f32{curr_pos.x + curr_sz.x / 2.0, curr_pos.y + curr_sz.y / 2.0}

	best_win: ^window.window = nil
	best_dist: f32 = 1e9

	for w in t.windows {
		if w == curr_win do continue

		w_pos := window.get_position(w)
		w_sz := window.get_size(w)
		w_center := [2]f32{w_pos.x + w_sz.x / 2.0, w_pos.y + w_sz.y / 2.0}

		dx := w_center.x - curr_center.x
		dy := w_center.y - curr_center.y

		is_valid := false
		switch dir {
		case .Left:
			is_valid = dx < -1.0 && abs(dy) < (curr_sz.y / 2.0 + w_sz.y / 2.0)
		case .Right:
			is_valid = dx > 1.0 && abs(dy) < (curr_sz.y / 2.0 + w_sz.y / 2.0)
		case .Up:
			is_valid = dy < -1.0 && abs(dx) < (curr_sz.x / 2.0 + w_sz.x / 2.0)
		case .Down:
			is_valid = dy > 1.0 && abs(dx) < (curr_sz.x / 2.0 + w_sz.x / 2.0)
		}

		if is_valid {
			dist := dx * dx + dy * dy
			if dist < best_dist {
				best_dist = dist
				best_win = w
			}
		}
	}

	if best_win != nil {
		for w, idx in t.windows {
			if w == best_win {
				t.focused_window = idx
				break
			}
		}
		update_active_window(t)
	}
}

cycle_focused_window :: proc(t: ^tab) {
	if len(t.windows) > 1 {
		t.focused_window = (t.focused_window + 1) % len(t.windows)
		update_active_window(t)
	}
}

preview_handle_key :: proc(t: ^tab, key: keybind.key) -> bool {
	return false
}

handle_key :: proc(t: ^tab, key: keybind.key) -> bool {
	if get_focused_window_mode(t) == .Normal {
		if keybind.handle(&t.key_binder, key) {
			return true
		}
	}
	return false
}

add_window :: proc(t: ^tab, w: ^window.window) {
	append(&t.windows, w)
	if len(t.windows) == 1 {
		t.focused_window = 0
	}
	update_active_window(t)
}

update_active_window :: proc(t: ^tab) {
	for w, idx in t.windows {
		window.set_active(w, idx == t.focused_window)
	}
}

focused_window :: proc(t: ^tab) -> ^window.window {
	if t.focused_window >= 0 && t.focused_window < len(t.windows) {
		return t.windows[t.focused_window]
	}
	return nil
}

get_focused_window_mode :: proc(t: ^tab) -> window.mode {
	win := focused_window(t)
	if win != nil {
		return window.get_mode(win)
	}
	return .Normal
}

get_focused_window_font_size :: proc(t: ^tab) -> f32 {
	win := focused_window(t)
	if win != nil {
		return window.get_font_size(win)
	}
	return 18.0
}

handle_command :: proc(t: ^tab, name: string, args: []string) -> bool {
	if command.execute(&t.cmd_binder, name, args) do return true

	win := focused_window(t)
	if win != nil {
		return window.handle_command(win, name, args)
	}

	return false
}

close_window :: proc(t: ^tab, force: bool) -> (bool, bool) {
	win := focused_window(t)
	if win == nil do return false, false

	if !force && win.buffer != nil && .Is_Updated in win.buffer.flags {
		open_elsewhere := false
		if t.is_buffer_open_elsewhere.call != nil {
			open_elsewhere = t.is_buffer_open_elsewhere.call(
				t.is_buffer_open_elsewhere.env,
				win.buffer,
				win,
			)
		} else {
			for w in t.windows {
				if w != win && w.buffer == win.buffer {
					open_elsewhere = true
					break
				}
			}
		}

		if !open_elsewhere {
			inputline.set_error("Error: No write since last change (add ! to override)")
			return false, false
		}
	}

	if len(t.windows) > 1 {
		close_focused_window(t)
		return true, true
	}

	return true, false
}
