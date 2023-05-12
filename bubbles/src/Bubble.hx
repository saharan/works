import muun.la.Vec2;

class Bubble {
	public var area:Float;
	public var anchor:HalfEdge;
	public var dead:Bool = false;

	public function new(area:Float, anchor:HalfEdge) {
		this.area = area;
		this.anchor = anchor;
		forEachEdge(e -> e.bubble = this);
	}

	public function updateEdges():Void {
		forEachEdge(e -> e.bubble = this);
	}

	public function preSolve():Void {
		updateEdges();
	}

	public function solve():Void {
		var currentArea = 0.0;
		var length = 0.0;
		final nsum = Vec2.zero;
		var numVs = 0;

		forEachEdge(e -> {
			final v1 = e.v;
			final v2 = e.next.v;
			final p1 = v1.pos + v1.vel;
			final p2 = v2.pos + v2.vel;
			v1.updateNormal(e);
			nsum += v1.n;
			currentArea += 0.5 * p1.cross(p2);
			if (e.twin.bubble != this) {
				length += (p2 - p1).length;
				numVs++;
			}
		});
		final pCoeff = 0.2;
		final pressure = (area - currentArea) / length * pCoeff;
		final shift = -nsum * (pressure / numVs);
		forEachEdge(e -> {
			if (e.twin.bubble != this) {
				final v = e.v;
				v.vel += v.n * pressure + shift;
			}
		});
	}

	public function size():Int {
		var res = 0;
		forEachEdge(e -> res++);
		return res;
	}

	public function isSmall():Bool {
		var e = anchor;
		var count = 0;
		do {
			if (++count > 8)
				return false;
			e = e.next;
		} while (e != anchor);
		return true;
	}

	public function destroy():Void {
		forEachEdge(e -> e.bubble = null);
		dead = true;
	}

	extern public inline function forEachEdge(f:(e:HalfEdge) -> Void):Void {
		var e = anchor;
		var count = 0;
		do {
			if (++count > 10000) {
				var e = anchor;
				final a = [];
				for (_ in 0...100) {
					final end = a.contains(e.id);
					a.push(e.id);
					if (end)
						break;
					e = e.next;
				}
				throw "wrong topology: " + a;
			}
			f(e);
			e = e.next;
		} while (e != anchor);
	}
}
