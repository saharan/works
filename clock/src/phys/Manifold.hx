package phys;

import muun.la.Vec2;

class Manifold {
	public var num:Int = 0;
	public final ps:Array<ManifoldPoint> = [new ManifoldPoint(), new ManifoldPoint()];

	public function new() {
	}

	public function clear():Void {
		num = 0;
	}

	public inline function add():ManifoldPoint {
		return ps[num++];
	}

	public function flip():Void {
		if (num >= 1) {
			ps[0].flip();
			if (num >= 2)
				ps[1].flip();
		}
	}
}
