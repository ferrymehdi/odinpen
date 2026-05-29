package sessionmanager

import "../core/render"
import "../finder"
import "../session"

draw :: proc(r: ^render.renderer_state, m: ^session_manager, remaining_space: render.rect) {
	session_inst := get_active_session(m)
	if session_inst == nil {
		return
	}

	session.draw(r, session_inst, remaining_space)

	if m.session_finder != nil {
		finder.draw(r, m.session_finder, remaining_space)
	}
}
