package phys;

import muun.la.Vec2;

class Box extends Shape {
	/** half extents */
	public final h:Vec2 = Vec2.zero;

	public function new(halfWidth:Float, halfHeight:Float) {
		super(Box(this));
		h.set(halfWidth, halfHeight);
	}

	override function computeMass():Void {
		area = 4 * h.dot(h);
		inertia = h.dot(h) / 3;
	}

	override function updateAABB():Void {
		final ex = rot.col0.abs() * h.x;
		final ey = rot.col1.abs() * h.y;
		aabb.set(p - ex - ey, p + ex + ey);
	}
}
