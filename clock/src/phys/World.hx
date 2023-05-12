package phys;

import muun.la.Vec3;
import haxe.ds.Vector;
import muun.la.Vec2;

class World {
	public final bs:Array<Body> = [];
	public final cs:Array<Contact> = [];
	public final g:Vec2 = Vec2.of(0, -0.015);
	public var iter:Int = 20;

	var recording:Bool = false;
	var frameCount:Int = 0;
	final frames:Array<Array<Float>> = [];

	final contactPool:Vector<Contact> = new Vector(4096);

	public function new() {
		for (i in 0...contactPool.length) {
			contactPool[i] = new Contact();
		}
	}

	public function step(backward:Bool = false):Void {
		if (backward) {
			stepBackward();
		} else {
			stepForward();
		}
		if (recording) {
			final frame = [];
			frames.push(frame);
			for (b in bs) {
				frame.push(b.p.x);
				frame.push(b.p.y);
				frame.push(b.ang);
				frame.push(b.v.x);
				frame.push(b.v.y);
				frame.push(b.av);
			}
		}
	}

	public function startRec():Void {
		frames.resize(0);
		recording = true;
	}

	public function stopRec():Void {
		cs.resize(0);
		recording = false;
	}

	public function playRec(rev:Bool = false):Bool {
		if (frames.length == 0)
			return true;
		if (rev) {
			frameCount = (frameCount + frames.length - 1) % frames.length;
		}
		final frame = frames[frameCount];
		var idx = 0;
		for (b in bs) {
			b.p.x = frame[idx++];
			b.p.y = frame[idx++];
			b.ang = frame[idx++];
			b.v.x = frame[idx++];
			b.v.y = frame[idx++];
			b.av = frame[idx++];
			b.sync();
		}
		final end = frameCount == (rev ? 0 : frames.length);
		if (!rev) {
			frameCount = (frameCount + 1) % frames.length;
		}
		return end;
	}

	function stepForward():Void {
		checkCollision();
		for (b in bs) {
			if (b.invM > 0)
				b.v += g;
		}
		for (c in cs) {
			c.preSolveForward();
		}
		for (t in 0...iter) {
			for (c in cs) {
				c.solveForward();
			}
		}
		for (b in bs) {
			b.p += b.v;
			b.ang += b.av;
			b.sync();
		}
	}

	function stepBackward():Void {
		checkCollision();
		for (b in bs) {
			b.v <<= -b.v;
			b.av = -b.av;
		}
		for (c in cs) {
			c.preSolveBackward();
		}
		for (b in bs) {
			if (b.invM > 0)
				b.v += g;
		}
		for (t in 0...iter) {
			for (c in cs) {
				c.solveBackward();
			}
		}
		for (b in bs) {
			b.p += b.v;
			b.ang += b.av;
			b.sync();

			b.v <<= -b.v;
			b.av = -b.av;
		}
	}

	function checkCollision():Void {
		cs.resize(0);
		final n = bs.length;
		final m = new Manifold();
		for (i in 0...n) {
			for (j in i + 1...n) {
				m.clear();
				final b1 = bs[i];
				final b2 = bs[j];
				if (b1.invM == 0 && b2.invM == 0)
					continue;
				if (!b1.shape.aabb.intersects(b2.shape.aabb))
					continue;
				switch [b1.shape.type, b2.shape.type] {
					case [Circle(c1), Circle(c2)]:
						CircleCollider.collide(c1, c2, m);
					case [Circle(c1), Box(b2)]:
						CircleBoxCollider.collide(c1, b2, m);
					case [Box(b1), Circle(c2)]:
						CircleBoxCollider.collide(c2, b1, m);
						m.flip();
					case [Box(b1), Box(b2)]:
						BoxCollider.collide(b1, b2, m);
				}
				if (m.num >= 1) {
					cs.push(contactPool[cs.length].set(b1, b2, m.ps[0]));
					if (m.num >= 2) {
						cs.push(contactPool[cs.length].set(b1, b2, m.ps[1]));
					}
				}
			}
		}
	}
}
