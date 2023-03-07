package phys;

import muun.la.Vec2;

class CircleBoxCollider {
	public static function collide(c:Circle, b:Box, m:Manifold):Void {
		final d = c.p - b.p;
		final ld = b.rot.t * d; // local pos of circle in box
		final lp2 = ld.max(-b.h).min(b.h); // local closest point
		final d2 = (lp2 - ld).lengthSq;
		if (d2 == 0) {
			final d1 = b.h + lp2;
			final d2 = b.h - lp2;
			final ln2 = Vec2.zero;
			final depth = if (d1.x < d1.y) {
				if (d2.x < d2.y) {
					if (d1.x < d2.x) { // d1x
						ln2.x = -1;
						lp2.x = -b.h.x;
						d1.x;
					} else { // d2x
						ln2.x = 1;
						lp2.x = b.h.x;
						d2.x;
					}
				} else {
					if (d1.x < d2.y) { // d1x
						ln2.x = -1;
						lp2.x = -b.h.x;
						d1.x;
					} else { // d2y
						ln2.y = 1;
						lp2.y = b.h.y;
						d2.y;
					}
				}
			} else {
				if (d2.x < d2.y) {
					if (d1.y < d2.x) { // d1y
						ln2.y = -1;
						lp2.y = -b.h.y;
						d1.y;
					} else { // d2x
						ln2.x = 1;
						lp2.x = b.h.x;
						d2.x;
					}
				} else {
					if (d1.y < d2.y) { // d1y
						ln2.y = -1;
						lp2.y = -b.h.y;
						d1.y;
					} else { // d2y
						ln2.y = 1;
						lp2.y = b.h.y;
						d2.y;
					}
				}
			}
			final n = b.rot * ln2;
			final rp2 = b.rot * lp2;
			m.add().set(-n * c.r, rp2, n, depth);
		} else if (d2 > 0 && d2 < c.r * c.r) {
			final rp2 = b.rot * lp2;
			final n = (c.p - (rp2 + b.p)).normalized;
			final depth = c.r - Math.sqrt(d2);
			m.add().set(-n * c.r, rp2, n, depth);
		}
	}
}
