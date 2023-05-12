package phys;

import muun.la.Vec2;

class ManifoldPoint {
	public final rp1:Vec2 = Vec2.zero;
	public final rp2:Vec2 = Vec2.zero;
	public final n:Vec2 = Vec2.zero;
	public var depth:Float;

	public function new() {
	}

	public inline function set(rp1:Vec2, rp2:Vec2, n:Vec2, depth:Float):Void {
		this.rp1 <<= rp1;
		this.rp2 <<= rp2;
		this.n <<= n;
		this.depth = depth;
	}

	public function flip():Void {
		final tmp = rp1.copy();
		rp1 <<= rp2;
		rp2 <<= tmp;
		n <<= -n;
	}
}
