import muun.la.Vec2;

class Edge {
	public var v1(get, never):Vertex;
	public var v2(get, never):Vertex;
	public final e:HalfEdge;

	public var doNotSwapCount:Int = 0;
	public var dyingCount:Int = 0;
	public var dead:Bool = false;

	final imp:Vec2 = Vec2.zero;

	public function new(e:HalfEdge) {
		this.e = e;
		e.e = this;
		e.twin.e = this;
	}

	extern inline function get_v1():Vertex {
		return e.v;
	}

	extern inline function get_v2():Vertex {
		return e.twin.v;
	}

	public function preSolve():Void {
		imp << Vec2.zero;
	}

	public function solve():Void {
		if (v1.invMass == 0 && v2.invMass == 0)
			return;
		final p1 = v1.pos + v1.vel;
		final p2 = v2.pos + v2.vel;
		final d = p1 - p2;
		final m = 1 / (v1.invMass + v2.invMass);
		final cfm = 4;
		final dimp = (-d * m - cfm * imp) / (1 + cfm);
		final pimp = imp.copy();
		imp += dimp;
		final maxImp = 2;
		if (imp.lengthSq > maxImp * maxImp) {
			imp *= maxImp / imp.length;
		}
		dimp << imp - pimp;
		v1.vel += v1.invMass * dimp;
		v2.vel -= v2.invMass * dimp;
	}
}
