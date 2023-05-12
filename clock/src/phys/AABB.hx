package phys;

import muun.la.Vec2;

class AABB {
	public final min:Vec2 = Vec2.zero;
	public final max:Vec2 = Vec2.zero;

	public function new() {
	}

	public inline function set(min:Vec2, max:Vec2):Void {
		this.min <<= min;
		this.max <<= max;
	}

	public function intersects(a:AABB):Bool {
		return min.x <= a.max.x && max.x >= a.min.x && min.y <= a.max.y && max.y >= a.min.y;
	}
}
