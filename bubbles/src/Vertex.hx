import muun.la.Vec3;
import muun.la.Mat2;
import muun.la.Vec2;

class Vertex {
	public final pos:Vec2 = Vec2.zero;
	public final vel:Vec2 = Vec2.zero;
	public final n:Vec2 = Vec2.zero;
	public final color:Vec3;
	public var hue:Float;
	public var invMass:Float = 1;

	static var idCount = 0;

	public final vi:VertexIndex;
	public final id = ++idCount;

	public var e:HalfEdge = null;

	static inline final MAX_VELOCITY:Float = 6.0;
	static var globalTime:Int = 0;

	var visitTime:Int = 0;

	public function new(pos:Vec2, vi:VertexIndex) {
		this.pos <<= pos;
		this.vi = vi;
		color = Vec3.of(Math.random(), Math.random(), Math.random());
		hue = Math.random();
	}

	public function update():Void {
		pos <<= pos + vel;
		vel *= 0.99;
		if (vel.lengthSq > MAX_VELOCITY * MAX_VELOCITY) {
			vel *= MAX_VELOCITY / vel.length;
		}
	}

	public function isNear(target:Vertex, maxDist:Int):Bool {
		globalTime++;
		var q1 = [];
		var q2 = [];
		var found = false;
		q1.push(this);
		visitTime = globalTime;
		for (_ in 0...maxDist) {
			while (q1.length > 0) {
				final v = q1.pop();
				v.forEachEdge(e -> {
					final v2 = e.twin.v;
					if (v2.visitTime != globalTime) {
						v2.visitTime = globalTime;
						if (v2 == target)
							found = true;
						q2.push(v2);
					}
				});
				if (found)
					return true;
			}
			final tmp = q1;
			q1 = q2;
			q2 = tmp;
		}
		return false;
	}

	public function distance(target:Vertex):Int {
		globalTime++;
		var q1 = [];
		var q2 = [];
		var found = false;
		q1.push(this);
		var dist = 0;
		while (q1.length > 0) {
			dist++;
			while (q1.length > 0) {
				final v = q1.pop();
				v.forEachEdge(e -> {
					final v2 = e.twin.v;
					if (v2.visitTime != globalTime) {
						v2.visitTime = globalTime;
						if (v == target)
							found = true;
						q2.push(v2);
					}
				});
				if (found)
					return dist;
			}
			final tmp = q1;
			q1 = q2;
			q2 = tmp;
		}
		return -1;
	}

	public function applyAirDrag(e:HalfEdge, power:Float):Void {
		final p0 = e.prev.v.pos;
		final p1 = pos;
		final p2 = e.twin.v.pos;
		final n1 = -(p1 - p0).star.normalized;
		final n2 = -(p2 - p1).star.normalized;
		final n = (n1 + n2).normalized;
		final t = n.star;
		final w = power;
		final wind = n * w;
		vel <<= vel + wind * Math.abs(t.dot(vel));
	}

	extern inline function wind(p:Vec2, time:Float):Float {
		return ((Vec2.of(p.x + p.y, p.x - p.y)) * 0.05).map(Math.sin).dot(Vec2.one) * 0.3;
	}

	extern public inline function forEachEdge(f:(e:HalfEdge) -> Void):Void {
		var count = 0;
		var edge = e;
		do {
			f(edge);
			edge = edge.twin.next;
			if (++count > 10000)
				throw "wrong topology";
		} while (edge != e && edge != null);
	}

	public function edgeCount():Int {
		var res = 0;
		forEachEdge(_ -> res++);
		return res;
	}

	public function updateNormal(e:HalfEdge):Void {
		final prev = e.prev.v;
		final next = e.next.v;
		final p0 = prev.pos + prev.vel;
		final p1 = pos + vel;
		final p2 = next.pos + next.vel;
		final n1 = -(p1 - p0).star.normalized;
		final n2 = -(p2 - p1).star.normalized;
		n <<= (n1 + n2).normalized;
	}
}
