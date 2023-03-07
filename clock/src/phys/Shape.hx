package phys;

import muun.la.Mat2;
import muun.la.Vec2;

class Shape {
	public final type:ShapeType;
	public var area:Float = 0;
	public var inertia:Float = 0;
	public final p:Vec2 = Vec2.zero;
	public var ang:Float = 0;
	public final rot:Mat2 = Mat2.id;
	public final aabb:AABB = new AABB();

	function new(type:ShapeType) {
		this.type = type;
	}

	public function computeMass():Void {
	}

	public function updateAABB():Void {
	}
}
