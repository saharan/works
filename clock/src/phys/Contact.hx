package phys;

import muun.la.Mat2;
import muun.la.Vec2;

class Contact {
	public final lp1:Vec2 = Vec2.zero;
	public final lp2:Vec2 = Vec2.zero;
	public final rp1:Vec2 = Vec2.zero;
	public final rp2:Vec2 = Vec2.zero;
	public final p1:Vec2 = Vec2.zero;
	public final p2:Vec2 = Vec2.zero;
	public var b1:Body = null;
	public var b2:Body = null;
	public final n:Vec2 = Vec2.zero;
	public final t:Vec2 = Vec2.zero;
	public var depth:Float = 0;

	var friction:Float = 0;
	var target:Float = 0;
	var invMass:Float = 0;

	var invM:Mat2 = Mat2.id;
	var massN:Float = 0;
	var massT:Float = 0;

	final nl1:Vec2 = Vec2.zero;
	final nl2:Vec2 = Vec2.zero;
	final tl1:Vec2 = Vec2.zero;
	final tl2:Vec2 = Vec2.zero;
	var na1:Float = 0;
	var na2:Float = 0;
	var ta1:Float = 0;
	var ta2:Float = 0;
	var cn1:Float = 0;
	var cn2:Float = 0;
	var ct1:Float = 0;
	var ct2:Float = 0;

	var impN:Float = 0;
	var impT:Float = 0;
	var frictionDir:Float = 0;

	public function new() {
	}

	public inline function set(b1:Body, b2:Body, mp:ManifoldPoint):Contact {
		this.b1 = b1;
		this.b2 = b2;
		rp1 <<= mp.rp1;
		rp2 <<= mp.rp2;
		lp1 <<= b1.rot.t * rp1;
		lp2 <<= b2.rot.t * rp2;
		p1 <<= b1.p + rp1;
		p2 <<= b2.p + rp2;
		n <<= mp.n;
		t <<= n.star;
		depth = mp.depth;
		return this;
	}

	public function preSolveForward():Void {
		final rv = b1.v - b2.v + b1.av * rp1.star - b2.av * rp2.star;
		final rvn = rv.dot(n);
		final restitution = Math.sqrt(b1.restitution * b2.restitution);
		friction = Math.sqrt(b1.friction * b2.friction);
		target = if (rvn < -Consts.BOUNCE_THRESHOLD) {
			-restitution * rvn;
		} else {
			0;
		}
		if (depth > Consts.LINEAR_SLOP) {
			final sep = (depth - Consts.LINEAR_SLOP) * Consts.POSITIONAL_BAUMGARTE;
			if (target < sep)
				target = sep;
		}
		impN = 0;
		impT = 0;

		computeMass();
	}

	public function preSolveBackward():Void {
		final rv = b1.v - b2.v + b1.av * rp1.star - b2.av * rp2.star;
		final rvn = rv.dot(n);
		final restitution = Math.sqrt(b1.restitution * b2.restitution);
		friction = Math.sqrt(b1.friction * b2.friction);

		var minTarget = 0.0;
		var maxTarget = 0.0;
		if (rvn > -Consts.BOUNCE_EPS) {
			minTarget = 0;
			maxTarget = Consts.BOUNCE_THRESHOLD;
		} else {
			maxTarget = minTarget = -rvn / restitution;
		}
		final rvt = rv.dot(t);
		if (rvt < -Consts.FRICTION_EPS) {
			frictionDir = -1;
		} else if (rvt > Consts.FRICTION_EPS) {
			frictionDir = 1;
		} else {
			frictionDir = 0;
		}

		target = minTarget;
		if (Math.random() < 0.05)
			target = maxTarget;

		impN = 0;
		impT = 0;

		computeMass();
	}

	function computeMass():Void {
		cn1 = rp1.cross(n);
		ct1 = rp1.cross(t);
		cn2 = rp2.cross(n);
		ct2 = rp2.cross(t);
		final invM1 = b1.invM;
		final invM2 = b2.invM;
		final invI1 = b1.invI;
		final invI2 = b2.invI;
		invM.e00 = invM1 + invM2 + invI1 * cn1 * cn1 + invI2 * cn2 * cn2;
		invM.e11 = invM1 + invM2 + invI1 * ct1 * ct1 + invI2 * ct2 * ct2;
		invM.e01 = invI1 * cn1 * ct1 + invI2 * cn2 * ct2;
		invM.e10 = invM.e01;
		massN = 1 / invM.e00;
		massT = 1 / invM.e11;
		nl1 <<= n * invM1;
		nl2 <<= n * invM2;
		tl1 <<= t * invM1;
		tl2 <<= t * invM2;
		na1 = cn1 * invI1;
		na2 = cn2 * invI2;
		ta1 = ct1 * invI1;
		ta2 = ct2 * invI2;
	}

	extern inline function min(a:Float, b:Float):Float {
		return a < b ? a : b;
	}

	extern inline function max(a:Float, b:Float):Float {
		return a > b ? a : b;
	}

	extern inline function clamp(a:Float, min:Float, max:Float):Float {
		return a < min ? min : a > max ? max : a;
	}

	public function solveForward():Void {
		final rvn = (b1.v - b2.v).dot(n) + b1.av * cn1 - b2.av * cn2;
		final pimpN = impN;
		impN = max(impN + (target - rvn) * massN, 0);
		final dimpN = impN - pimpN;
		b1.v += nl1 * dimpN;
		b2.v -= nl2 * dimpN;
		b1.av += na1 * dimpN;
		b2.av -= na2 * dimpN;

		final rvt = (b1.v - b2.v).dot(t) + b1.av * ct1 - b2.av * ct2;
		final pimpT = impT;
		final maxImpT = impN * friction;
		impT = clamp(impT - rvt * massT, -maxImpT, maxImpT);
		final dimpT = impT - pimpT;
		b1.v += tl1 * dimpT;
		b2.v -= tl2 * dimpT;
		b1.av += ta1 * dimpT;
		b2.av -= ta2 * dimpT;
	}

	public function solveBackward():Void {
		final rvn = (b1.v - b2.v).dot(n) + b1.av * cn1 - b2.av * cn2;
		final pimpN = impN;
		impN = max(impN + (target - rvn) * massN, 0);
		final dimpN = impN - pimpN;
		b1.v += nl1 * dimpN;
		b2.v -= nl2 * dimpN;
		b1.av += na1 * dimpN;
		b2.av -= na2 * dimpN;

		final rvt = (b1.v - b2.v).dot(t) + b1.av * ct1 - b2.av * ct2;
		final pimpT = impT;
		final maxImpT = impN * friction;
		if (frictionDir == 0) {
			impT = clamp(impT - rvt * massT, -maxImpT, maxImpT);
		} else {
			impT = maxImpT * frictionDir;
		}
		final dimpT = impT - pimpT;
		b1.v += tl1 * dimpT;
		b2.v -= tl2 * dimpT;
		b1.av += ta1 * dimpT;
		b2.av -= ta2 * dimpT;
	}
}
