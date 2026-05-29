package tab

import "../core/render"
import "../window"

draw :: proc(r: ^render.renderer_state, t: ^tab, space: render.rect) -> render.rect {
	draw_layout_node(r, t.layout, space)
	return space
}

draw_layout_node :: proc(r: ^render.renderer_state, node: ^Layout_Node, space: render.rect) {
	if node == nil do return

	if !node.is_split {
		if node.window != nil {
			window.draw(r, node.window, space)

			window.set_position(node.window, {space.x, space.y})
			window.set_size(node.window, {space.w, space.h})
		}
		return
	}

	n := len(node.children)
	if n == 0 do return

	if node.dir == .Vertical {
		child_w := space.w / f32(n)
		for child, i in node.children {
			child_space := render.rect {
				x = space.x + f32(i) * child_w,
				y = space.y,
				w = child_w,
				h = space.h,
			}
			draw_layout_node(r, child, child_space)
		}
	} else {
		child_h := space.h / f32(n)
		for child, i in node.children {
			child_space := render.rect {
				x = space.x,
				y = space.y + f32(i) * child_h,
				w = space.w,
				h = child_h,
			}
			draw_layout_node(r, child, child_space)
		}
	}
}
