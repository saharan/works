import muun.la.Vec3;
import pot.util.XorShift;
import haxe.Timer;
import muun.la.Mat2;
import muun.la.Vec2;
import pot.graphics.gl.Graphics;
import js.Browser;
import pot.core.App;

class Main extends App {
	var g:Graphics;
	final bs:Array<Bubble> = [];
	final vs:Array<Vertex> = [];
	final es:Array<Edge> = [];
	final ps:Array<Particle> = [];
	var v1:Vertex;
	var v2:Vertex;

	static inline final DEFAULT_EDGE_LENGTH:Float = 8.0;
	static inline final SPLIT_THRESHOLD:Float = 1.25;
	static inline final MERGE_THRESHOLD:Float = 0.8;
	static inline final SPLIT_MERGE_DAMP:Float = 0.9;
	static inline final MIN_AREA:Float = 250;
	static inline final PI:Float = 3.141592653589793;
	static inline final TWO_PI:Float = PI * 2;

	final BLACK:Vec3 = Vec3.of(0, 0, 0.4);

	final mposDelta:Vec2 = Vec2.zero;

	final grid:Grid<Vertex> = new Grid();

	final hits:Array<Array<Vertex>> = [];

	var wand:Item;
	var fan:Item;
	var needle:Item;
	var dragging:Item = null;
	var draggingBubble:Bubble = null;
	final rand:XorShift = new XorShift(12345);

	override function setup():Void {
		g = new Graphics(canvas);
		g.init2D();
		pot.frameRate(Fixed(60));

		init();

		// Browser.window.setTimeout(pot.start, 500);
		pot.start();
	}

	extern inline function abs(a:Float):Float {
		return a < 0 ? -a : a;
	}

	extern inline function max(a:Float, b:Float):Float {
		return a > b ? a : b;
	}

	extern inline function min(a:Float, b:Float):Float {
		return a < b ? a : b;
	}

	extern inline function clamp(a:Float, min:Float, max:Float):Float {
		return a < min ? min : a > max ? max : a;
	}

	extern inline function createVertex(pos:Vec2):Vertex {
		final vi = grid.createVertex();
		final v = new Vertex(pos, vi);
		grid.setVertex(vi, v);
		vs.push(v);
		return v;
	}

	extern inline function destroyVertex(v:Vertex):Void {
		if (!vs.remove(v))
			throw "does not exist";
		grid.destroyVertex(v.vi);
	}

	function destroyEdge(e:Edge):Void {
		if (e.dead)
			throw "already removed";
		if (!es.remove(e))
			throw "does not exist";
		e.dead = true;
	}

	function init():Void {
		grid.destroyVertices();
		vs.resize(0);
		bs.resize(0);
		es.resize(0);

		final center = Vec2.of(pot.width, pot.height) * 0.5;
		fan = new Item(center.x - 120, center.y, 0, 1, 30, Fan);
		wand = new Item(center.x - 50, center.y + 20, 0, 1, 40, Wand);
		needle = new Item(center.x + 150, center.y, -1, 0, 25, Needle);
		final rad = 50;
		// final vs1 = createBubble(center.x - 300, center.y, rad * 0.6);
		// final vs2 = createBubble(center.x - 100, center.y, rad * 1.8);
		// final vs3 = createBubble(center.x, center.y, rad * 1.0);
		// final vs4 = createBubble(center.x + 100, center.y, rad * 1.2);
		// final vs5 = createBubble(center.x + 200, center.y, rad * 1.4);
		// connectBubbles(vs2, vs3);
		// connectBubbles(vs3, vs4);
		// connectBubbles(vs4, vs5);

		// var pvs = null;
		// for (i in 0...100) {
		// 	final vs = createBubble(center.x + (Math.random() * 2 - 1) * 200, center.y + (Math.random() * 2 - 1) * 200, rad * (0.25 +
		// 		Math.random() * 1));
		// 	if (pvs != null)
		// 		connectBubbles(pvs, vs);
		// 	pvs = vs;
		// }

		v1 = createVertex(Vec2.of(30, 30) - Vec2.of(0, 20));
		v2 = createVertex(Vec2.of(30, 30) + Vec2.of(0, 20));
		final e = new HalfEdge(v1);
		e.makeTwin(v2);
		v1.invMass = 0;
		v2.invMass = 0;
		es.push(new Edge(e));
	}

	function connectBubbles(vs1:Array<Vertex>, vs2:Array<Vertex>):Void {
		final m1 = Vec2.zero;
		final m2 = Vec2.zero;
		for (v in vs1) {
			m1 <<= v.pos;
		}
		for (v in vs2) {
			m2 <<= v.pos;
		}
		m1 <<= m1 / vs1.length;
		m2 <<= m2 / vs2.length;
		final d12 = m2 - m1;
		var v1 = null;
		var v2 = null;
		var maxDot = -1e9;
		for (v in vs1) {
			final dot = (v.pos - m1).dot(d12);
			if (dot > maxDot && v.edgeCount() == 2) {
				maxDot = dot;
				v1 = v;
			}
		}
		maxDot = -1e9;
		for (v in vs2) {
			final dot = -(v.pos - m2).dot(d12);
			if (dot > maxDot && v.edgeCount() == 2) {
				maxDot = dot;
				v2 = v;
			}
		}
		final e1 = v1.e.bubble == null ? v1.e : v1.e.twin.next;
		final e2 = v2.e.bubble == null ? v2.e : v2.e.twin.next;
		final e12 = new HalfEdge(v1);
		final e21 = e12.makeTwin(v2);
		e12.setPrev(e1.prev);
		e21.setPrev(e2.prev);
		e12.setNext(e2);
		e21.setNext(e1);
		es.push(new Edge(e12));
	}

	function createBubble(x:Float, y:Float, r:Float):Array<Vertex> {
		final vs = [];
		final c = Vec2.of(x, y);
		final div = Math.ceil(2 * r * PI / DEFAULT_EDGE_LENGTH);
		for (i in 0...div) {
			final ang = 2 * PI * i / div;
			final pos = c + (Mat2.rot(ang) * Vec2.of(r, 0));
			final v = createVertex(pos);
			vs.push(v);
		}
		final es = [];
		for (i in 0...div) {
			final e = new HalfEdge(vs[i]);
			es.push(e);
			e.makeTwin(vs[(i + 1) % div]);
			this.es.push(new Edge(e));
		}
		for (i in 0...div) {
			es[i].setNext(es[(i + 1) % div]);
			es[(i + 1) % div].twin.setNext(es[i].twin);
		}
		bs.push(new Bubble(PI * r * r, es[0]));
		return vs;
	}

	function addParticles(e:HalfEdge):Void {
		final p1 = e.v.pos;
		final p2 = e.twin.v.pos;
		final num = 2;
		for (i in 0...num) {
			final p = p1 + rand.nextFloat() * (p2 - p1);
			final color = Vec3.zero;
			setRainbowColor(color, rand.nextFloat(), 0);
			ps.push(new Particle(p, color));
		}
	}

	function removeVertex(v:Vertex, force:Bool = false):Bool {
		if (v.edgeCount() != 2 || !force && v.e.bubble == null && v.e.twin.bubble == null)
			return false;
		final e1 = v.e;
		final e2 = v.e.twin.next;
		if (e1.e.dead || e2.e.dead)
			return false;
		final b1 = e1.bubble;
		final b2 = e2.bubble;
		if (b1 != null) {
			b1.destroy();
			bs.remove(b1);
		}
		if (b2 != null) {
			b2.destroy();
			bs.remove(b2);
		}
		var toRemove = [];
		var e = e1;
		var end1 = null;
		var end2 = null;
		do {
			if (e.v.edgeCount() != 2) {
				end1 = e;
				break;
			}
			toRemove.push(e);
			e = e.next;
		} while (e != e1);

		if (e == e1) {
			for (e in toRemove) {
				destroyVertex(e.v);
				destroyEdge(e.e);
				addParticles(e);
			}
			// trace("removed vertex " + v.id);
			return true;
		}

		end1.v.e = end1;
		end1.setPrev(end1.prev.twin.prev);

		var count = 0;
		e = e2;
		while (true) {
			if (++count > 10000)
				throw "wrong topology";
			if (e.v.edgeCount() != 2) {
				end2 = e;
				break;
			}
			toRemove.push(e);
			e = e.next;
		}

		end2.v.e = end2;
		end2.setPrev(end2.prev.twin.prev);

		for (i => e in toRemove) {
			if (i > 0)
				destroyVertex(e.v);
			destroyEdge(e.e);
			addParticles(e);
		}

		if (!end1.e.dead) {
			final area1 = loopArea(end1);
			if (area1 > 0) {
				// trace("A");
				bs.push(new Bubble(area1, end1));
			}
		}
		if (end1.e.dead || !onSameLoop(end1, end2)) {
			final area2 = loopArea(end2);
			if (area2 > 0) {
				// trace("B");
				bs.push(new Bubble(area2, end2));
			}
		}
		// trace("removed vertex " + v.id);

		return true;
	}

	extern inline function fanCenter(wand:Bool):Vec2 {
		return fan.v - fan.size * (wand ? 2 : 1) * fan.direction.star;
	}

	function setRainbowColor(to:Vec3, hue:Float, shift:Float):Void {
		final res = (hue + Vec3.of(0, 0.3, 0.7)) * TWO_PI + frameCount * 0.06 + shift;
		res <<= Vec3.of(Math.sin(res.x), Math.sin(res.y), Math.sin(res.z));
		res <<= res * Vec3.of(0.5, 0.4, 0.5) + Vec3.of(0.5, 0.4, 0.5);
		to.x = res.x; // hack: prevent new
		to.y = res.y;
		to.z = res.z;
	}

	function applyWind(v:Vertex):Void {
		if (v.invMass == 0)
			return;
		final inWand = v.edgeCount() == 2 && v.e.bubble == null && v.e.twin.bubble == null;
		final scale = inWand ? 3 : 1;
		final ex = fan.direction;
		final ey = -ex.star;
		final p = v.pos;
		final d = p - fanCenter(inWand);
		final dist = Vec2.of(max(0, abs(ex.dot(d)) - 30) * 10, ey.dot(d)).length;
		final weight = Math.sqrt(max(0, 1 - dist * 1e-2));
		v.vel += ey * weight * scale * 0.3;
	}

	function interact():Void {
		final mpos = Vec2.zero;
		var pressing = false;
		var dpressing = 0;

		if (input.mouse.hasInput) {
			final mouse = input.mouse;
			mpos <<= Vec2.of(mouse.x, mouse.y);
			pressing = mouse.left;
			dpressing = mouse.dleft;
		} else if (input.touches.length > 0) {
			final touch = input.touches[0];
			mpos <<= Vec2.of(touch.x, touch.y);
			pressing = touch.touching;
			dpressing = touch.dtouching;
			if (pressing) {
				mposDelta += (Vec2.of(0, -50) - mposDelta) * 0.1;
			}
			if (dpressing == 1) {
				mposDelta <<= Vec2.zero;
			}
			mpos <<= mpos + mposDelta;
		}

		final cmpos = Vec2.of(clamp(mpos.x, 30, pot.width - 30), clamp(mpos.y, 30, pot.height - 30));

		switch dpressing {
			case -1:
				dragging = null;
				draggingBubble = null;
			case 1:
				final items = [wand, fan, needle];
				var minDist = 40.0;
				for (item in items) {
					final dist = (item.v - mpos).length;
					if (dist < minDist) {
						minDist = dist;
						dragging = item;
					}
				}
				if (dragging != null) {
					dragging.drag(cmpos);
				} else {
					var minMeanDist = 1e9;
					for (b in bs) {
						var count = 0;
						var meanDist = 0.0;
						var numVs = 0;
						b.forEachEdge(e -> {
							final p1 = e.v.pos;
							final p2 = e.twin.v.pos;
							final t = (mpos.y - p1.y) / (p2.y - p1.y);
							if (t >= 0 && t < 1) {
								if (mpos.x < p1.x + t * (p2.x - p1.x))
									count++;
							}
							numVs++;
							meanDist += (mpos - p1).length;
						});
						if (count % 2 == 1) {
							meanDist /= numVs;
							if (meanDist < minMeanDist) {
								minMeanDist = meanDist;
								draggingBubble = b;
							}
						}
					}
				}
			case 0:
				if (pressing) {
					if (dragging != null)
						dragging.drag(cmpos);
					if (draggingBubble != null) {
						if (draggingBubble.dead) {
							if (draggingBubble.anchor.bubble != null) {
								draggingBubble = draggingBubble.anchor.bubble;
							} else {
								draggingBubble = null;
							}
						}
						if (draggingBubble != null) {
							final mean = Vec2.zero;
							var numVs = 0;
							draggingBubble.forEachEdge(e -> {
								mean <<= mean + e.v.pos;
								numVs++;
							});
							mean <<= mean * (1 / numVs);
							final force = (mpos - mean) * 0.02;
							final maxForce = 0.8;
							if (force.lengthSq > maxForce) {
								force <<= force * (maxForce / force.length);
							}
							draggingBubble.forEachEdge(e -> {
								e.v.vel += force;
							});
						}
					}
				}
		}

		v1.pos <<= wand.v1;
		v2.pos <<= wand.v;
	}

	override function update():Void {
		interact();
		final subSteps = 2;
		for (step in 0...subSteps) {
			final pes = es.copy(); // TODO: slow
			for (e in pes) {
				if (!e.dead)
					checkSplit(e);
				if (!e.dead)
					checkMerge(e);
			}

			final toRemove = [];
			final gridSize = DEFAULT_EDGE_LENGTH * MERGE_THRESHOLD * 0.5;
			final invGridSize = 1 / gridSize;
			grid.clear();
			hits.resize(0);
			for (v in vs) {
				applyWind(v);

				final gx = Math.floor(v.pos.x * invGridSize);
				final gy = Math.floor(v.pos.x * invGridSize);
				for (dx in -1...2) {
					for (dy in -1...2) {
						grid.forEach(grid.getIndex(gx + dx, gy + dy), (_, v2) -> {
							final d = v.pos - v2.pos;
							if (d.lengthSq < gridSize * gridSize && !v.isNear(v2, 5)) {
								if (!collide(v, v2)) {
									toRemove.push(v.vel.length < v2.vel.length ? v.e.e : v2.e.e);
								}
								hits.push([v, v2]);
							}
						});
					}
				}
				grid.register(v.vi, grid.getIndex(gx, gy));
			}
			for (e in es) {
				e.preSolve();
				e.e.bubble = null;
				e.e.twin.bubble = null;
			}
			for (b in bs)
				b.preSolve();

			for (e in es)
				e.solve();
			for (b in bs)
				b.solve();
			for (e in es)
				e.solve();
			for (b in bs)
				b.solve();
			for (e in es)
				e.solve();

			for (v in vs) {
				v.update();
				if (v.invMass > 0) {
					if (v.pos.x < 0)
						v.vel.x += -v.pos.x * 0.1;
					if (v.pos.y < 0)
						v.vel.y += -v.pos.y * 0.1;
					if (v.pos.x > pot.width)
						v.vel.x += (pot.width - v.pos.x) * 0.1;
					if (v.pos.y > pot.height)
						v.vel.y += (pot.height - v.pos.y) * 0.1;
				}
			}

			final needleRad = DEFAULT_EDGE_LENGTH;
			final needleRad2 = needleRad * needleRad;
			final needleTip1 = needle.v2 - needle.direction * needleRad;
			final needleTip2 = needleTip1 - needle.direction * needleRad;
			for (v in vs) {
				if (min((v.pos - needleTip1).lengthSq, (v.pos - needleTip2).lengthSq) < needleRad2) {
					if (removeVertex(v))
						break;
				}
			}

			for (e in es) {
				if (e.e.bubble == e.e.twin.bubble) {
					if (++e.dyingCount > 1)
						toRemove.push(e);
				} else {
					e.dyingCount = 0;
					if (rand.nextFloat() < 0.00002)
						toRemove.push(e);
				}
			}
			for (e in toRemove) {
				if (!e.dead)
					removeVertex(e.e.v, true) || removeVertex(e.e.twin.v, true);
			}

			{
				var e = v1.e;
				var area = 0.0;
				var totalLength = 0.0;
				while (e != null) {
					e.e.dyingCount = 0; // make it immortal
					final p1 = e.v.pos;
					final p2 = e.twin.v.pos;
					totalLength += (p2 - p1).length;
					area += p1.cross(p2);
					e = e.next;
				}
				area += v2.pos.cross(v1.pos);
				final sign = area < 0 ? -1 : 1;

				final nearFan = 1 - clamp(((wand.v - fanCenter(true)).length - 50) * 0.05, 0, 1);
				final angleCoeff = 0.06 + (0.1 - 0.06) * nearFan;
				final strength = 0.5 + (0.2 - 0.5) * nearFan;
				e = v1.e;
				var dist = 0.0;
				while (e != null) {
					final v = e.v;
					if (v.invMass > 0) {
						final angle = abs(totalLength * 0.5 - dist) * angleCoeff;
						final pos = max(0, Math.sin(angle));
						final neg = min(0, Math.sin(angle));
						v.applyAirDrag(e, (pos * 0.2 + neg) * sign * strength);
					}
					dist += (e.v.pos - e.twin.v.pos).length;
					e = e.next;
				}
			}
			makeBubbles();
		}
		for (v in vs) {
			setRainbowColor(v.color, v.hue, v.pos.y * 0.1);
		}
		{
			var i = 0;
			while (i < ps.length) {
				ps[i].update();
				if (ps[i].dead) {
					ps[i] = ps[ps.length - 1];
					ps.pop();
					continue;
				}
				i++;
			}
		}
	}

	function collide(v1:Vertex, v2:Vertex):Bool {
		if (v1.edgeCount() != 2 || v2.edgeCount() != 2)
			return true;
		if (v1.e.bubble == null && v1.e.twin.bubble == null)
			return true;
		if (v2.e.bubble == null && v2.e.twin.bubble == null)
			return true;
		final e1a = v1.e;
		final e1b = v1.e.twin.next;
		final e2a = v2.e;
		final e2b = v2.e.twin.next;
		return checkEdgePair(e1a, e2a) || checkEdgePair(e1a, e2b) || checkEdgePair(e1b, e2a) || checkEdgePair(e1b, e2b);
	}

	function checkEdgePair(e1:HalfEdge, e2:HalfEdge):Bool {
		e1.v.updateNormal(e1);
		e2.v.updateNormal(e2);
		if (e1.v.n.dot(e2.v.n) > 0)
			return false;
		if (onSameLoop(e1, e2)) {
			final inner = e1.bubble != null;
			final e12 = connectEdge(e1, e2);
			final e21 = e12.twin;
			final areaA = loopArea(e12);
			final areaB = loopArea(e21);
			if (inner) {
				if (areaA > 0 && areaB > 0) {
					final b = e1.bubble;
					b.destroy();
					bs.remove(b);
					bs.push(new Bubble(max(MIN_AREA, areaA), e12));
					bs.push(new Bubble(max(MIN_AREA, areaB), e21));
					es.push(new Edge(e12));
					return true;
				}
			} else if (areaA * areaB < 0) {
				if (areaA > 0) {
					bs.push(new Bubble(max(MIN_AREA, areaA), e12));
				} else {
					bs.push(new Bubble(max(MIN_AREA, areaB), e21));
				}
				es.push(new Edge(e12));
				return true;
			}
			disconnectEdge(e12);
		} else {
			final inner1 = e1.bubble != null;
			final inner2 = e2.bubble != null;
			if (inner1 && inner2)
				return false;
			if (!inner1 && !inner2) {
				final e12 = connectEdge(e1, e2);
				es.push(new Edge(e12));
				// trace("A area = " + loopArea(e12));
				// loopAreaDebug(e12);
				return true;
			}
			final e12 = connectEdge(e1, e2);
			final e21 = e12.twin;
			final newArea = loopArea(e12);
			if (newArea > 0) {
				if (inner1) {
					e12.bubble = e21.bubble = e1.bubble;
					e1.bubble.area = max(MIN_AREA, newArea);
				} else {
					e12.bubble = e21.bubble = e2.bubble;
					e2.bubble.area = max(MIN_AREA, newArea);
				}
				e12.bubble.updateEdges();
				es.push(new Edge(e12));
				// trace("B area = " + loopArea(e12));
				// loopAreaDebug(e12);
				return true;
			}
			disconnectEdge(e12);
		}
		return false;
	}

	function connectEdge(e1:HalfEdge, e2:HalfEdge):HalfEdge {
		final e1p = e1.prev;
		final e2p = e2.prev;
		final e12 = new HalfEdge(e1.v);
		final e21 = e12.makeTwin(e2.v);
		e1p.setNext(e12).setNext(e2);
		e2p.setNext(e21).setNext(e1);
		e12.bubble = e2.bubble;
		e21.bubble = e1.bubble;
		return e12;
	}

	function disconnectEdge(e12:HalfEdge):Void {
		final e21 = e12.twin;
		final e1p = e12.prev;
		final e2p = e21.prev;
		final e1 = e21.next;
		final e2 = e12.next;
		e1.setPrev(e1p);
		e2.setPrev(e2p);
		e1.v.e = e1;
		e2.v.e = e2;
	}

	function onSameLoop(e1:HalfEdge, e2:HalfEdge):Bool {
		var e = e1;
		do {
			if (e == e2)
				return true;
			e = e.next;
		} while (e != e1);
		return false;
	}

	function loopArea(e1:HalfEdge):Float {
		var e = e1;
		var area = 0.0;
		do {
			final v1 = e.v;
			final v2 = e.next.v;
			area += v1.pos.cross(v2.pos) * 0.5;
			e = e.next;
		} while (e != e1);
		return area;
	}

	function isInnerLoop(e1:HalfEdge):Bool {
		return loopArea(e1) > 0;
	}

	function makeBubbles():Void {
		if (v1.e.next == null || v1.e.next.next == null)
			return;

		final r2 = Math.pow(DEFAULT_EDGE_LENGTH * MERGE_THRESHOLD, 2);
		var e = v1.e.next.next; // start from the 3rd vertex
		while (e.next != null) {
			final vFrom = e.v;
			var e2 = e.next;
			var dist = 1;
			while (e2.next != null) {
				if (dist++ >= 5) {
					final vTo = e2.v;
					final len2 = (vFrom.pos - vTo.pos).lengthSq;
					if (len2 < r2) {
						break;
					}
				}
				e2 = e2.next;
			}
			if (e2.next == null) {
				// didn't hit
				e = e.next;
			} else {
				final e1 = e;

				final e01 = e1.prev;
				final e23 = e2;
				final e12 = new HalfEdge(e1.v);
				final e21 = e12.makeTwin(e2.v);
				final e03 = new HalfEdge(e01.v);
				final e30 = e03.makeTwin(e23.twin.v);

				e03.setPrev(e01.prev);
				e03.setNext(e23.next);
				e30.setPrev(e23.next.twin);
				e30.setNext(e01.prev.twin);

				e12.setPrev(e01.next.twin);
				e12.setNext(e23.prev.twin);
				e21.setPrev(e23.prev);
				e21.setNext(e01.next);

				destroyEdge(e01.e);
				destroyEdge(e23.e);

				es.push(new Edge(e12));
				es.push(new Edge(e03));

				addBubble(e12);

				e = e03.next;
			}
		}
	}

	function addBubble(anchor:HalfEdge):Void {
		var e = anchor;
		var area = 0.0;
		do {
			final p1 = e.v.pos;
			final p2 = e.next.v.pos;
			area += 0.5 * p1.cross(p2);
			e = e.next;
		} while (e != anchor);
		if (area < 0) {
			anchor = anchor.twin;
			area = -area;
		}
		area += MIN_AREA * (0.75 + rand.nextFloat() * 0.5);
		bs.push(new Bubble(area, anchor));
	}

	function escape(e:HalfEdge):Void {
		if (e.bubble != null && e.bubble.anchor == e) {
			e.bubble.anchor = e.next;
			e.bubble = null;
		}
	}

	function checkSplit(e:Edge):Void {
		final v1 = e.v1;
		final v2 = e.v2;
		final p1 = v1.pos;
		final p2 = v2.pos;
		final len = (p2 - p1).length;
		if (len > DEFAULT_EDGE_LENGTH * SPLIT_THRESHOLD) {
			final mid = createVertex((p1 + p2) * 0.5);
			mid.vel <<= (v1.vel + v2.vel) * 0.5 * SPLIT_MERGE_DAMP;
			mid.color <<= 0.75 * Vec3.of(rand.nextFloat(), rand.nextFloat(), rand.nextFloat()) + 0.25 * (v1.color + v2.color) * 0.5;
			mid.hue = 0.75 * Math.random() + 0.25 * (v1.hue + v2.hue) * 0.5;
			final e12 = e.e;
			final e21 = e.e.twin;

			final e1m = new HalfEdge(v1);
			final em1 = e1m.makeTwin(mid);
			final em2 = new HalfEdge(mid);
			final e2m = em2.makeTwin(v2);
			e1m.bubble = em2.bubble = e12.bubble;
			em1.bubble = e2m.bubble = e21.bubble;
			escape(e12);
			escape(e21);
			e1m.setPrev(e12.prev);
			e1m.setNext(em2);
			em2.setNext(e12.next);
			e2m.setPrev(e21.prev);
			e2m.setNext(em1);
			em1.setNext(e21.next);
			destroyEdge(e);
			es.push(new Edge(e1m));
			es.push(new Edge(em2));

			// trace("split! -" + v1.id + "-" + v2.id + "- -> -" + v1.id + "-" + mid.id + "-" + v2.id + "- (" + frameCount + ")");
		}
	}

	function checkMerge(e:Edge):Void {
		final e1 = e.e;
		final e2 = e1.twin;
		if (e1.prev == null || e1.next == null || e2.prev == null || e2.next == null)
			return;
		if (e1.bubble != null && e1.bubble.isSmall())
			return;
		if (e2.bubble != null && e2.bubble.isSmall())
			return;
		if (e1.prev == e1.next || e2.prev == e2.next)
			return;
		final v1 = e.v1;
		final v2 = e.v2;
		final p1 = v1.pos;
		final p2 = v2.pos;
		final len = (p2 - p1).length;
		if (len < DEFAULT_EDGE_LENGTH * MERGE_THRESHOLD) {
			if (v1.edgeCount() == 3 && v2.edgeCount() == 3) {
				swapEdge(e);
				return;
			}

			escape(e.e);
			escape(e.e.twin);
			final mid = createVertex((p1 + p2) * 0.5);
			mid.vel <<= (v1.vel + v2.vel) * 0.5 * SPLIT_MERGE_DAMP;
			mid.color <<= (v1.color + v2.color) * 0.5;
			mid.hue = (v1.hue + v2.hue) * 0.5;
			// reroot
			{
				var count = 0;
				var e = e1.twin.next;
				while (e != e1) {
					e.changeRoot(mid);
					e = e.twin.next;
					if (++count > 10000)
						throw "wrong topology";
				}
				e = e2.twin.next;
				while (e != e2) {
					e.changeRoot(mid);
					e = e.twin.next;
					if (++count > 10000)
						throw "wrong topology";
				}
			}
			// skip the edge
			e1.prev.setNext(e1.next);
			e2.prev.setNext(e2.next);
			destroyEdge(e);
			destroyVertex(v1);
			destroyVertex(v2);
			// trace("merged! -" + v1.id + "-" + v2.id + "- -> -" + mid.id + "- (" + frameCount + ")");
		}
	}

	function swapEdge(e:Edge):Void {
		if (e.doNotSwapCount-- > 0) {
			return;
		}
		e.doNotSwapCount = 4;
		final v1 = e.v1;
		final v2 = e.v2;
		final e12 = e.e;
		final e21 = e12.twin;
		final ea1 = e12.prev;
		final e2b = e12.next;
		final ed2 = e21.prev;
		final e1c = e21.next;
		final e1a = ea1.twin;
		final eb2 = e2b.twin;
		final e2d = ed2.twin;
		final ec1 = e1c.twin;

		final ea2 = ea1;
		final e2a = e1a;
		final ed1 = ed2;
		final e1d = e2d;
		final va = ea1.v;
		final vb = eb2.v;
		final vc = ec1.v;
		final vd = ed2.v;
		final ab = (va.pos + vb.pos) * 0.5;
		final cd = (vc.pos + vd.pos) * 0.5;

		final mid = (v1.pos + v2.pos) * 0.5;
		v2.pos <<= (mid + ab) * 0.5;
		v1.pos <<= (mid + cd) * 0.5;

		escape(e12);
		escape(e21);

		ea2.setNext(e2b);
		ed1.setNext(e1c);
		ec1.setNext(e12).setNext(e2a);
		eb2.setNext(e21).setNext(e1d);

		e12.bubble = e2a.bubble;
		e21.bubble = e1d.bubble;

		e2a.changeRoot(v2);
		e1d.changeRoot(v1);
	}

	override function draw():Void {
		final debug = false;
		var ha = false;
		g.screen(pot.width, pot.height);
		g.inScene(() -> {
			g.clear(1, 1, 1);

			g.beginShape(Triangles);
			for (e in es) {
				if (e.e.bubble == null && e.e.twin.bubble == null)
					drawEdge(e, 1);
			}
			g.endShape();

			drawWand(0.8);
			drawFan(0.8);
			drawNeedle(0.8);

			g.color(0);
			g.beginShape(Lines);

			if (debug) {
				for (e in es) {
					g.vertex(e.e.v.pos);
					g.vertex(e.e.twin.v.pos);
				}
				for (v in vs)
					drawVertex(v);
				g.color(1, 0, 0, 0.5);
				for (h in hits) {
					g.vertex(h[0].pos);
					g.vertex(h[1].pos);
				}
				for (b in bs) {
					b.forEachEdge(e -> {
						if (e.bubble != b) {
							g.color(1, 0, 1, 0.5);
							ha = true;
						} else {
							g.color(0, 0, 1, 0.5);
						}
						e.v.updateNormal(e);
						e.next.v.updateNormal(e.next);
						g.vertex(e.v.pos - e.v.n * 3);
						g.vertex(e.next.v.pos - e.next.v.n * 3);
					});
				}
			}
			g.endShape();

			if (!debug) {
				g.beginShape(Triangles);
				for (b in bs) {
					drawBubble(b, 1);
				}
				for (p in ps) {
					drawParticle(p);
				}
				g.endShape();
			}
		});
		if (ha)
			throw "ha";
	}

	function drawParticle(p:Particle):Void {
		g.color(p.color);
		final size = p.size;
		final p1 = p.pos + Vec2.of(-size, -size);
		final p2 = p.pos + Vec2.of(-size, size);
		final p3 = p.pos + Vec2.of(size, size);
		final p4 = p.pos + Vec2.of(size, -size);
		g.vertex(p1);
		g.vertex(p2);
		g.vertex(p3);
		g.vertex(p1);
		g.vertex(p3);
		g.vertex(p4);
	}

	function drawBubble(b:Bubble, thickness:Float):Void {
		b.forEachEdge(e -> {
			final e1 = e;
			final e2 = e.next;
			final v1 = e1.v;
			final v2 = e2.v;
			v1.updateNormal(e1);
			v2.updateNormal(e2);
			final p1 = v1.pos + v1.n * thickness;
			final p2 = v2.pos + v2.n * thickness;
			final p3 = v2.pos - v2.n * thickness;
			final p4 = v1.pos - v1.n * thickness;
			g.color(v1.color);
			g.vertex(p1);
			g.color(v2.color);
			g.vertex(p2);
			g.vertex(p3);
			g.color(v1.color);
			g.vertex(p1);
			g.color(v2.color);
			g.vertex(p3);
			g.color(v1.color);
			g.vertex(p4);
		});
	}

	extern inline function line(a:Vec2, b:Vec2, ca:Vec3, cb:Vec3, thickness:Float):Void {
		final n = (b - a).normalized;
		final t = n.star;
		final p1 = a + t * thickness;
		final p2 = a - t * thickness;
		final p3 = b - t * thickness;
		final p4 = b + t * thickness;
		g.color(ca);
		g.vertex(p1);
		g.vertex(p2);
		g.color(cb);
		g.vertex(p3);
		g.color(ca);
		g.vertex(p1);
		g.color(cb);
		g.vertex(p3);
		g.vertex(p4);
	}

	extern inline function drawOvalVertices(p1:Vec2, p2:Vec2, rad2:Float, color:Vec3, thickness:Float):Void {
		final center = (p1 + p2) * 0.5;
		final div = 16;
		final ex = p1 - center;
		final ey = ex.star.normalized * rad2;
		final center = (p1 + p2) * 0.5;
		for (i in 0...div) {
			final ang1 = i / div * TWO_PI;
			final ang2 = (i + 1) / div * TWO_PI;
			final p1 = center + ex * Math.cos(ang1) + ey * Math.sin(ang1);
			final p2 = center + ex * Math.cos(ang2) + ey * Math.sin(ang2);
			line(p1, p2, color, color, thickness);
		}
	}

	function drawFan(thickness:Float):Void {
		final p1 = fan.v1;
		final center = fan.v;
		final ex = p1 - center;
		final wings = 4;
		final size = ex.length;
		g.beginShape(Triangles);
		for (i in 0...wings) {
			final ang = i / wings * TWO_PI + frameCount * 0.2;
			final cos = Math.cos(ang);
			drawOvalVertices(center + ex * cos * 0.1, center + ex * cos, size * 0.3, BLACK, thickness);
		}
		g.endShape();
	}

	function drawNeedle(thickness:Float):Void {
		final p1 = needle.v1;
		final p2 = needle.v2;
		final tan = needle.direction.star;
		g.beginShape(Triangles);
		final p1a = p1 + tan * 5;
		final p1b = p1 - tan * 5;
		line(p1a, p1b, BLACK, BLACK, thickness);
		line(p1a, p2, BLACK, BLACK, thickness);
		line(p1b, p2, BLACK, BLACK, thickness);
		g.endShape();
	}

	function drawWand(thickness:Float):Void {
		final p1 = wand.v1;
		final center = (wand.v + p1) * 0.5;
		final ex = p1 - center;
		final ey = ex.star * 0.5;
		final div = 16;
		final TWO_PI = PI * 2;
		g.beginShape(Triangles);
		g.color(1);
		for (i in 0...div) {
			final ang1 = i / div * TWO_PI;
			final ang2 = (i + 1) / div * TWO_PI;
			g.vertex(center);
			g.vertex(center + ex * Math.cos(ang1) + ey * Math.sin(ang1));
			g.vertex(center + ex * Math.cos(ang2) + ey * Math.sin(ang2));
		}
		drawOvalVertices(p1, wand.v, ey.length, BLACK, thickness);
		line(wand.v, wand.v2, BLACK, BLACK, thickness);
		g.endShape();
	}

	function drawEdge(e:Edge, thickness:Float):Void {
		line(e.v1.pos, e.v2.pos, e.v1.color, e.v2.color, thickness);
	}

	function drawVertex(v:Vertex):Void {
		v.edgeCount();
		final p = v.pos;
		g.vertex(p + Vec2.of(-3, -3));
		g.vertex(p + Vec2.of(3, 3));
		g.vertex(p + Vec2.of(-3, 3));
		g.vertex(p + Vec2.of(3, -3));
	}

	static function main():Void {
		new Main(cast Browser.document.getElementById("canvas"), false, false);
	}
}
