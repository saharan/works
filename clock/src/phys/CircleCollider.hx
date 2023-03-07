package phys;

import muun.la.Vec2;

class CircleCollider {
	public static function collide(c1:Circle, c2:Circle, m:Manifold):Void {
		final d = c1.p - c2.p;
		final d2 = d.lengthSq;
		final n = d2 > 0 ? d.normalized : Vec2.ex;
		final r = c1.r + c2.r;
		if (d2 < r * r) {
			final depth = r - Math.sqrt(d2);
			m.add().set(-n * c1.r, n * c2.r, n, depth);
		}
	}
}
