package phys;

import muun.la.Mat2;
import muun.la.Vec2;

class Body {
	public final p:Vec2 = Vec2.zero;
	public final v:Vec2 = Vec2.zero;
	public var av:Float = 0;
	public var invM:Float = 0;
	public var invI:Float = 0;
	public var ang:Float = 0;
	public final rot:Mat2 = Mat2.id;
	public var shape:Shape = null;

	public var restitution:Float = 0.9;
	public var friction:Float = 0.1;

	public function new(p:Vec2) {
		this.p <<= p;
	}

	public function setShape(shape:Shape, density:Float = 1):Body {
		this.shape = shape;
		shape.computeMass();
		final mass = shape.area * density;
		final inertia = mass * shape.inertia;
		invM = mass > 0 ? 1 / mass : 0;
		invI = inertia > 0 ? 1 / inertia : 0;
		sync();
		return this;
	}

	public function sync():Void {
		rot <<= Mat2.rot(ang);
		shape.ang = ang;
		shape.rot <<= rot;
		shape.p <<= p;
		shape.updateAABB();
	}
}
