package phys;

import muun.la.Mat2;
import muun.la.Vec2;

class BoxCollider {
	static final v1s:Array<Vec2> = [Vec2.zero, Vec2.zero, Vec2.zero, Vec2.zero];
	static final v2s:Array<Vec2> = [Vec2.zero, Vec2.zero, Vec2.zero, Vec2.zero];
	static final n1s:Array<Vec2> = [Vec2.zero, Vec2.zero, Vec2.zero, Vec2.zero];
	static final n2s:Array<Vec2> = [Vec2.zero, Vec2.zero, Vec2.zero, Vec2.zero];

	public static function collide(b1:Box, b2:Box, m:Manifold):Void {
		v1s[0] <<= b1.p + b1.rot * (Vec2.of(-1, -1) * b1.h);
		v1s[1] <<= b1.p + b1.rot * (Vec2.of(-1, 1) * b1.h);
		v1s[2] <<= b1.p + b1.rot * (Vec2.of(1, 1) * b1.h);
		v1s[3] <<= b1.p + b1.rot * (Vec2.of(1, -1) * b1.h);
		v2s[0] <<= b2.p + b2.rot * (Vec2.of(-1, -1) * b2.h);
		v2s[1] <<= b2.p + b2.rot * (Vec2.of(-1, 1) * b2.h);
		v2s[2] <<= b2.p + b2.rot * (Vec2.of(1, 1) * b2.h);
		v2s[3] <<= b2.p + b2.rot * (Vec2.of(1, -1) * b2.h);
		n1s[0] <<= -b1.rot.col0;
		n1s[1] <<= b1.rot.col1;
		n1s[2] <<= b1.rot.col0;
		n1s[3] <<= -b1.rot.col1;
		n2s[0] <<= -b2.rot.col0;
		n2s[1] <<= b2.rot.col1;
		n2s[2] <<= b2.rot.col0;
		n2s[3] <<= -b2.rot.col1;

		var minIndex = -1;

		inline function calcSep(v1s:Array<Vec2>, v2s:Array<Vec2>, n1s:Array<Vec2>):Float {
			var minDepth = 1e9;
			minIndex = -1;
			for (i in 0...4) {
				final p = v1s[i];
				final n = n1s[i];
				var minDist = 1e9;
				for (j in 0...4) {
					final dist = (v2s[j] - p).dot(n);
					if (dist < minDist) {
						minDist = dist;
					}
				}
				final depth = -minDist;
				if (depth < minDepth) {
					minDepth = depth;
					minIndex = i;
				}
			}
			return minDepth;
		}

		final d1 = calcSep(v1s, v2s, n1s);
		final i1 = minIndex;
		if (d1 < 0)
			return;
		final d2 = calcSep(v2s, v1s, n2s);
		final i2 = minIndex;
		if (d2 < 0)
			return;

		inline function calcInc(nref:Vec2, ns:Array<Vec2>):Int {
			var minDot = 1.0;
			var res = -1;
			for (i in 0...4) {
				final dot = nref.dot(ns[i]);
				if (dot < minDot) {
					minDot = dot;
					res = i;
				}
			}
			return res;
		}
		if (d1 < d2) {
			final n = n1s[i1];
			final r1 = v1s[i1];
			final r2 = v1s[i1 + 1 & 3];
			final inc = calcInc(n1s[i1], n2s);
			final i1 = v2s[inc];
			final i2 = v2s[inc + 1 & 3];
			clipEdge(b1.p, b2.p, true, r1, r2, i1, i2, n, m);
		} else {
			final n = n2s[i2];
			final r1 = v2s[i2];
			final r2 = v2s[i2 + 1 & 3];
			final inc = calcInc(n2s[i2], n1s);
			final i1 = v1s[inc];
			final i2 = v1s[inc + 1 & 3];
			clipEdge(b2.p, b1.p, false, r1, r2, i1, i2, n, m);
		}
	}

	static extern inline function clipEdge(rp:Vec2, ip:Vec2, isRef1:Bool, r1:Vec2, r2:Vec2, i1:Vec2, i2:Vec2, n:Vec2, m:Manifold):Void {
		do {
			final r1i1 = i1 - r1;
			final r1i2 = i2 - r1;
			final t = n.star;
			{
				final d1 = t.dot(r1i1);
				final d2 = t.dot(r1i2);
				if (d1 > 0 && d2 > 0)
					break;
				if (d1 * d2 < 0) {
					final t = d1 / (d1 - d2);
					i2 <<= i1 + (i2 - i1) * t;
				}
			}
			final r2i1 = i1 - r2;
			final r2i2 = i2 - r2;
			{
				final d1 = t.dot(r2i1);
				final d2 = t.dot(r2i2);
				if (d1 < 0 && d2 < 0)
					break;
				if (d1 * d2 < 0) {
					final t = d1 / (d1 - d2);
					i1 <<= i1 + (i2 - i1) * t;
				}
			}
			final d1 = (r1 - i1).dot(n);
			final d2 = (r1 - i2).dot(n);
			if (d1 > 0) {
				m.add().set(i1 + n * d1 - rp, i1 - ip, -n, d1);
			}
			if (d2 > 0) {
				m.add().set(i2 + n * d2 - rp, i2 - ip, -n, d2);
			}
			if (!isRef1)
				m.flip();
		} while (false);
	}
}
