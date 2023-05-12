import pot.graphics.gl.FovMode;
import pot.graphics.gl.Shader;
import pot.graphics.gl.Graphics;
import js.Browser;
import muun.la.Mat2;
import muun.la.Vec2;
import muun.la.Vec3;
import phys.Body;
import phys.Box;
import phys.Circle;
import pot.core.App;

class Main extends App {
	var g:Graphics;
	var playing:Bool = false;
	var phase:Int = 0; // 0: recording, 1: playing, 2: forwarding
	final layers:Array<Layer> = [];
	final preparing:Array<Layer> = [];
	var time:Float;
	final color:Vec3 = Vec3.zero;
	var alpha:Float = 1.0;
	final translation:Vec3 = Vec3.zero;
	final bgColor:Vec3 = Vec3.of(0.1, 0.05, 0.2);
	var shader:Shader;

	override function setup():Void {
		g = new Graphics(canvas);
		g.perspective(FovMin);
		g.init3D();

		shader = g.createShader(FogShader.vertexSource, FogShader.fragmentSource);
		g.shader(shader);

		init();

		pot.frameRate(Fixed(60));

		final ms = Date.now().getTime() % 1000;
		if (ms < 100 || ms > 900)
			Browser.window.setTimeout(pot.start, 500); // to avoid jittering
		else
			pot.start();
	}

	override function resized():Void {
		g.screen(pot.width, pot.height);
	}

	function init():Void {
		var time = Date.now().getTime() + 1000 * (Layer.NUM_FRAMES / Layer.SUBSTEPS) / 60;
		final l = new Layer(time);
		while (!l.ready()) {
			l.prepareNextFrame();
		}
		layers.push(l);
		preparing.push(new Layer(time += 1000));
	}

	override function update():Void {
		for (l in preparing) {
			if (!l.ready())
				l.prepareNextFrame();
		}
		if (layers[0].position() >= 2) {
			layers.shift();
		}
		if (frameCount % 60 == 59) {
			layers.push(preparing.shift());
			preparing.push(new Layer(Date.now().getTime() + 1000 + 1000 * (Layer.NUM_FRAMES / Layer.SUBSTEPS) / 60));
		}
		final ang = Math.PI * 2 * Date.now().getTime() / 1000 / 60;
		final scale = Vec3.of(0.15, 0.1, 0.2);
		bgColor <<= (Vec3.of(Math.cos(ang - Math.PI * 2 / 3), Math.cos(ang + Math.PI * 2 / 3), Math.cos(ang)) * 0.5 + 0.5) * scale;
		for (l in layers) {
			l.nextFrame();
		}
	}

	inline function abs(a:Float):Float {
		return a < 0 ? -a : a;
	}

	override function draw():Void {
		g.defaultUniformMap.set(FogShader.uniforms.bgColor.name, Vec3(bgColor.x, bgColor.y, bgColor.z));

		g.screen(pot.width, pot.height);
		g.inScene(() -> {
			g.clear(bgColor.x, bgColor.y, bgColor.z);
			g.lights();
			g.camera(Vec3.of(Layer.WIDTH * 0.75, Layer.HEIGHT * 1.6, Layer.DEPTH * 0.6), Vec3.of(Layer.WIDTH * 0.45, Layer.HEIGHT * 0, Layer.DEPTH * -0.3),
				Vec3.ey);
			g.beginShape(Triangles);
			for (l in layers) {
				translation.z = (l.position() - 1) * Layer.DEPTH;
				final t = 1 - abs(l.position() - 1);
				final c = Math.pow(t, 0.75);
				final c2 = Math.pow(t, 10);
				final tmp = if (l.secondsString.charAt(1) == "0") {
					bgColor + c * 0.7 + c2 * 1.0;
				} else {
					bgColor + c * 0.7 + c2 * 0.4;
				}
				color <<= tmp;
				alpha = c;
				for (b in l.w.bs)
					if (b.invM > 0)
						drawBody(b);
			}
			g.endShape();
		});
	}

	function drawBody(b:Body):Void {
		switch b.shape.type {
			case Circle(c):
				drawCircle(c);
			case Box(b):
				drawBox(b);
		}
	}

	function drawCircle(c:Circle):Void {
		final num = 16;
		for (t in 0...num) {
			final a1 = c.ang + (t - 0.5) / num * 2 * Math.PI;
			final a2 = c.ang + (t + 0.5) / num * 2 * Math.PI;
			final p1 = c.p + c.r * (Mat2.rot(a1) * Vec2.ex);
			final p2 = c.p + c.r * (Mat2.rot(a2) * Vec2.ex);
			g.vertex(p1.x, p1.y);
			g.vertex(p2.x, p2.y);
		}
		g.vertex(c.p.x, c.p.y);
		g.vertex(c.p.x + c.rot.col0.x * c.r, c.p.y + c.rot.col0.y * c.r);
	}

	inline function min(a:Float, b:Float):Float {
		return a < b ? a : b;
	}

	inline function clamp(a:Float, min:Float, max:Float):Float {
		return a < min ? min : a > max ? max : a;
	}

	function drawBox(b:Box):Void {
		final cr = color.x;
		final cg = color.y;
		final cb = color.z;
		final ca = alpha;
		function boxFace(normal:Vec3, v1:Vec3, v2:Vec3, v3:Vec3, v4:Vec3):Void {
			g.color(cr, cg, cb, ca);
			g.normal(normal.x, normal.y, normal.z);
			g.vertex(v1.x, v1.y, v1.z);
			g.vertex(v2.x, v2.y, v2.z);
			g.vertex(v3.x, v3.y, v3.z);
			g.vertex(v4.x, v4.y, v4.z);
			g.makeQuad();
			{
				final b1 = ca * 0.6 * clamp(1 - v1.y / 30, 0, 1);
				final b2 = ca * 0.6 * clamp(1 - v2.y / 30, 0, 1);
				final b3 = ca * 0.6 * clamp(1 - v3.y / 30, 0, 1);
				final b4 = ca * 0.6 * clamp(1 - v4.y / 30, 0, 1);
				if (b1 > 0 || b2 > 0 || b3 > 0 || b4 > 0) {
					g.normal(normal.x, -normal.y, normal.z);
					g.color(cr, cg, cb, b4);
					g.vertex(v4.x, -v4.y, v4.z);
					g.color(cr, cg, cb, b3);
					g.vertex(v3.x, -v3.y, v3.z);
					g.color(cr, cg, cb, b2);
					g.vertex(v2.x, -v2.y, v2.z);
					g.color(cr, cg, cb, b1);
					g.vertex(v1.x, -v1.y, v1.z);
					g.makeQuad();
				}
			}
			{
				final b1 = ca * 0.6 * clamp(1 - v1.x / 30, 0, 1);
				final b2 = ca * 0.6 * clamp(1 - v2.x / 30, 0, 1);
				final b3 = ca * 0.6 * clamp(1 - v3.x / 30, 0, 1);
				final b4 = ca * 0.6 * clamp(1 - v4.x / 30, 0, 1);
				if (b1 > 0 || b2 > 0 || b3 > 0 || b4 > 0) {
					g.normal(-normal.x, normal.y, normal.z);
					g.color(cr, cg, cb, b4);
					g.vertex(-v4.x, v4.y, v4.z);
					g.color(cr, cg, cb, b3);
					g.vertex(-v3.x, v3.y, v3.z);
					g.color(cr, cg, cb, b2);
					g.vertex(-v2.x, v2.y, v2.z);
					g.color(cr, cg, cb, b1);
					g.vertex(-v1.x, v1.y, v1.z);
					g.makeQuad();
				}
			}
			{
				final b1 = ca * 0.6 * clamp(1 - (Layer.WIDTH - v1.x) / 30, 0, 1);
				final b2 = ca * 0.6 * clamp(1 - (Layer.WIDTH - v2.x) / 30, 0, 1);
				final b3 = ca * 0.6 * clamp(1 - (Layer.WIDTH - v3.x) / 30, 0, 1);
				final b4 = ca * 0.6 * clamp(1 - (Layer.WIDTH - v4.x) / 30, 0, 1);
				if (b1 > 0 || b2 > 0 || b3 > 0 || b4 > 0) {
					g.normal(-normal.x, normal.y, normal.z);
					g.color(cr, cg, cb, b4);
					g.vertex(Layer.WIDTH * 2 - v4.x, v4.y, v4.z);
					g.color(cr, cg, cb, b3);
					g.vertex(Layer.WIDTH * 2 - v3.x, v3.y, v3.z);
					g.color(cr, cg, cb, b2);
					g.vertex(Layer.WIDTH * 2 - v2.x, v2.y, v2.z);
					g.color(cr, cg, cb, b1);
					g.vertex(Layer.WIDTH * 2 - v1.x, v1.y, v1.z);
					g.makeQuad();
				}
			}
		}

		final ex = b.rot.col0.extend(0);
		final ey = b.rot.col1.extend(0);
		final ez = Vec3.ez;
		final hw = b.h.x;
		final hh = b.h.y;
		final hd = min(b.h.x, b.h.y);
		final base = b.p.extend(0) + translation;
		final v1 = base - hw * ex - hh * ey - hd * ez;
		final v2 = base - hw * ex - hh * ey + hd * ez;
		final v3 = base - hw * ex + hh * ey - hd * ez;
		final v4 = base - hw * ex + hh * ey + hd * ez;
		final v5 = base + hw * ex - hh * ey - hd * ez;
		final v6 = base + hw * ex - hh * ey + hd * ez;
		final v7 = base + hw * ex + hh * ey - hd * ez;
		final v8 = base + hw * ex + hh * ey + hd * ez;
		boxFace(-ex, v1, v2, v4, v3);
		boxFace(ex, v5, v7, v8, v6);
		boxFace(-ey, v1, v5, v6, v2);
		boxFace(ey, v3, v4, v8, v7);
		boxFace(-ez, v1, v3, v7, v5);
		boxFace(ez, v2, v6, v8, v4);
	}

	static function main():Void {
		new Main(cast Browser.document.getElementById("canvas"));
	}
}
