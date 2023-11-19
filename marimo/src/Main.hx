import Shaders;
import js.Browser;
import js.html.InputElement;
import js.lib.Float32Array;
import muun.la.Vec3;
import pot.core.App;
import pot.graphics.gl.FovMode;
import pot.graphics.gl.Graphics;
import pot.graphics.gl.Object;
import pot.graphics.gl.RenderTexture;
import pot.graphics.gl.Shader;
import pot.graphics.gl.Texture;
import pot.util.ImageLoader;

class Main extends App {
	var g:Graphics;
	var marimo:Marimo = null;
	var obj:Object = null;

	static inline final GRAVITY:Float = 0.05;
	static inline final FLOOR_Y:Float = -1;
	static inline final RESTITUTION:Float = 0.5;
	static inline final SPHERE_DIV:Int = 58;

	var shadow:Texture;
	var ppos:RenderTexture;
	var pos:RenderTexture;
	var vel:RenderTexture;

	var renderShader:Shader;
	var colorShader:Shader;
	var solveShader:Shader;
	var copyShader:Shader;
	var updateVelShader:Shader;
	var updatePosShader:Shader;
	var hairLength:Float = 3;
	var hairVolume:Float = 0.6; // [0, 1]

	final color1:Vec3 = Vec3.of(0.1, 0.15, 0.12);
	final color2:Vec3 = Vec3.of(0.18, 0.5, 0.2);

	var shakeCount:Int = 0;
	var shake:Vec3 = Vec3.zero;
	var gravity:Bool = true;

	final roots:Array<Vec3> = [];
	final hairs:Array<Array<Vec3>> = [];
	var numHairs:Int = 0;
	var maxHairs:Int = 0;
	var rgbMode:Bool = false;
	var brightness:Float = 1;

	override function setup():Void {
		pot.frameRate(Fixed(60));
		g = new Graphics(canvas);
		g.init3D();
		g.blend(None);
		g.sphereDetails(16, 8);
		g.perspective(FovMin);
		initShaders();
		initTextures();
		init();
		initObject();
		initUI();
		ImageLoader.loadImages(["shadow.png"], bmps -> {
			shadow = g.loadBitmap(bmps[0]);
			pot.start();
		});
	}

	function initShaders():Void {
		colorShader = g.createShader(ColorShader.vertexSource, ColorShader.fragmentSource);
		renderShader = g.createShader(RenderShader.vertexSource, RenderShader.fragmentSource);
		solveShader = g.createShader(SolveShader.vertexSource, SolveShader.fragmentSource);
		copyShader = g.createShader(CopyShader.vertexSource, CopyShader.fragmentSource);
		updateVelShader = g.createShader(UpdateVelShader.vertexSource, UpdateVelShader.fragmentSource);
		updatePosShader = g.createShader(UpdatePosShader.vertexSource, UpdatePosShader.fragmentSource);
	}

	function initUI():Void {
		inline function getInput(name:String):InputElement {
			return cast Browser.document.getElementById(name);
		}
		final radius = getInput("radius");
		final amount = getInput("amount");
		final length = getInput("length");
		final volume = getInput("volume");
		final gravity = getInput("gravity");
		final rgb = getInput("rgb");
		radius.oninput = () -> {
			marimo.radius = clamp(radius.valueAsNumber, 1, 10);
		}
		amount.oninput = () -> {
			numHairs = Math.round(clamp(amount.valueAsNumber, 0.1, 1) * maxHairs);
		}
		length.oninput = () -> {
			hairLength = clamp(length.valueAsNumber, 1, 10);
		}
		volume.oninput = () -> {
			hairVolume = clamp(volume.valueAsNumber, 0.4, 1.0);
		}
		gravity.oninput = () -> {
			this.gravity = gravity.checked;
		}
		rgb.oninput = () -> {
			rgbMode = rgb.checked;
		}
	}

	function initTextures():Void {
		final w = Consts.c.TEX_WIDTH;
		final h = Consts.c.TEX_HEIGHT;
		ppos = new RenderTexture(g, w, h, Float32, 1, Nearest);
		pos = new RenderTexture(g, w, h, Float32, 1, Nearest);
		vel = new RenderTexture(g, w, h, Float32, 1, Nearest);
	}

	function initObject():Void {
		obj = g.createObject();
		obj.mode = Lines;
		// obj.mode = Points;
		final w = obj.writer;
		final div = Consts.c.HAIR_DIV;
		final hair = hairs[0];
		final off = w.numVertices;
		for (i => v in hair) {
			final t = i / (div - 1);
			w.color(color1 + (color2 - color1) * t * t);

			w.vertex(Vec3.zero, false);
		}
		for (i in 0...div - 1) {
			w.index(off + i);
			w.index(off + i + 1);
		}
		w.upload();
		maxHairs = hairs.length;
		numHairs = Math.round(maxHairs * 0.75);
	}

	function writePositions():Void {
		final w = Consts.c.TEX_WIDTH;
		final h = Consts.c.TEX_HEIGHT;
		final data = new Float32Array(w * h * 4);
		var i = 0;
		for (hair in hairs) {
			for (j => v in hair) {
				data[i++] = v.x;
				data[i++] = v.y;
				data[i++] = v.z;
				data[i++] = j <= 1 ? 0 : 1; // inverse mass
			}
		}
		ppos.data[0].upload(0, 0, w, h, data, false);
		pos.data[0].upload(0, 0, w, h, data, false);
	}

	function init():Void {
		marimo = new Marimo(5);
		marimo.pos <<= Vec3.of(0, 25, 0);
		marimo.avel.x = 0.04;
		roots.resize(0);
		hairs.resize(0);
		final vs = icosphereVerts(SPHERE_DIV);
		for (v in vs) {
			final v2 = v + (Vec3.of(Math.random(), Math.random(), Math.random()) * 2 - 1) * 0.05;
			final root = v2.normalized * marimo.radius;
			roots.push(root);
			hairs.push(makeHair(root));
		}
		for (i in 1...hairs.length) {
			final j = Std.random(i + 1);
			final tmp = hairs[i];
			hairs[i] = hairs[j];
			hairs[j] = tmp;
		}
		var n = 0;
		for (hair in hairs) {
			for (v in hair) {
				n++;
				final delta = (Vec3.of(Math.random(), Math.random(), Math.random()) * 2 - 1) * 0.03;
				delta -= delta.dot(v.normalized) * v.normalized;
				v += delta;
			}
		}
		trace(n);
		writePositions();
	}

	function makeHair(root:Vec3):Array<Vec3> {
		final dn = root.normalized * hairLength * Consts.c.INV_HAIR_DIV;
		final res = [];
		for (i in 0...Consts.c.HAIR_DIV) {
			res.push(root + dn * i);
		}
		return res;
	}

	function icosphereVerts(div:Int):Array<Vec3> {
		final p = 1.6180339887498948482;
		final vs = [
			Vec3.of(p, 1, 0),
			Vec3.of(-p, 1, 0),
			Vec3.of(p, -1, 0),
			Vec3.of(-p, -1, 0),
			Vec3.of(1, 0, p),
			Vec3.of(1, 0, -p),
			Vec3.of(-1, 0, p),
			Vec3.of(-1, 0, -p),
			Vec3.of(0, p, 1),
			Vec3.of(0, -p, 1),
			Vec3.of(0, p, -1),
			Vec3.of(0, -p, -1),
		];
		final tris = [
			[0, 8, 4],
			[0, 5, 10],
			[2, 4, 9],
			[2, 11, 5],
			[1, 6, 8],
			[1, 10, 7],
			[3, 9, 6],
			[3, 7, 11],
			[0, 10, 8],
			[1, 8, 10],
			[2, 9, 11],
			[3, 9, 11],
			[4, 2, 0],
			[5, 0, 2],
			[6, 1, 3],
			[7, 3, 1],
			[8, 6, 4],
			[9, 4, 6],
			[10, 5, 7],
			[11, 7, 5],
		];
		final res = [];
		for (v in vs)
			res.push(v);
		for (i in 0...12) {
			for (j in 0...i) {
				var has = false;
				for (tri in tris) {
					final hasI = tri[0] == i || tri[1] == i || tri[2] == i;
					final hasJ = tri[0] == j || tri[1] == j || tri[2] == j;
					if (hasI && hasJ) {
						has = true;
						break;
					}
				}
				if (!has)
					continue;
				final a = vs[i];
				final b = vs[j];
				final ab = b - a;
				for (i in 1...div - 1) {
					final t = i / (div - 1);
					res.push(a + ab * t);
				}
			}
		}
		for (tri in tris) {
			final a = vs[tri[0]];
			final b = vs[tri[1]];
			final c = vs[tri[2]];
			final ab = b - a;
			final bc = c - b;
			for (i in 1...div - 1) {
				for (j in 1...i) {
					final ti = i / (div - 1);
					final tj = j / (div - 1);
					final p = a + ab * ti + bc * tj;
					res.push(p);
				}
			}
		}
		final scale = 0.52573111211913360603;
		for (v in res) {
			v *= scale;
		}
		return res;
	}

	function setMap():Void {
		final map = g.defaultUniformMap;
		map.set(BaseShader.u.pposTex, Sampler(ppos.data[0]));
		map.set(BaseShader.u.posTex, Sampler(pos.data[0]));
		map.set(BaseShader.u.velTex, Sampler(vel.data[0]));
		map.set(BaseShader.u.radius, Float(marimo.radius));
		map.set(BaseShader.u.time, Float(frameCount / 60));
		map.set(BaseShader.u.hairCount, Int(numHairs));
		map.set(BaseShader.u.hairLength, Float(hairLength));
		map.set(BaseShader.u.hairVolume, Float(hairVolume));
		final c = marimo.pos;
		final rot = marimo.rot;
		map.set(BaseShader.u.center, Vec3(c.x, c.y, c.z));
		map.set(BaseShader.u.rot, Mat(3, 3,
			[rot.e00, rot.e10, rot.e20, rot.e01, rot.e11, rot.e21, rot.e02, rot.e12, rot.e22]));
	}

	extern inline function softCollide(normal:Vec3, depth:Float, hardThreshold:Float):Void {
		final rpos = -normal * marimo.radius;
		final rvn = marimo.vel.dot(normal);
		final hardness = min(1, depth / hardThreshold);
		final repel = depth < hardThreshold * 0.5 ? 0 : (depth - hardThreshold * 0.5) * 0.1;
		final nimp = max(0, -rvn) * (1 + RESTITUTION) * hardness + repel;
		final rvel = marimo.vel + marimo.avel.cross(rpos);
		final tangent = (rvel - normal * normal.dot(rvel)).normalized;
		final rvt = rvel.dot(tangent);
		final tmass = 1 + marimo.invI * tangent.cross(rpos).lengthSq;
		final mu = 0.5;
		final tmax = mu * nimp;
		final timp = clamp(tmass * -rvt, -tmax, tmax);
		final imp = normal * nimp + tangent * timp;
		marimo.vel += imp;
		marimo.avel += rpos.cross(imp) * marimo.invI;
		if (nimp > 0.1) {
			shakeCount = 15;
			shake <<= min(nimp, 10) * normal * 0.2;
		}
	}

	override function update():Void {
		final mpos = marimo.pos;
		final vel = marimo.vel;
		final avel = marimo.avel;
		vel *= 0.99;
		avel *= 0.99;
		if (gravity)
			vel += Vec3.of(0, -GRAVITY, 0);
		final pointer = input.pointer;
		if (pointer.down) {
			final delta = pointer.delta / pot.size;
			vel += Vec3.of(delta.x, 0, delta.y) * 10;
		}
		brightness += ((rgbMode ? 0.3 : 1) - brightness) * 0.1;

		final mins = Vec3.of(-25, 0, -25);
		final maxs = Vec3.of(25, 50, 25);
		final softHitRadius = hairLength * hairVolume;
		mins += marimo.radius + softHitRadius;
		maxs -= marimo.radius + softHitRadius;
		if (mpos.x < mins.x)
			softCollide(Vec3.ex, mins.x - mpos.x, softHitRadius);
		if (mpos.y < mins.y)
			softCollide(Vec3.ey, mins.y - mpos.y, softHitRadius);
		if (mpos.z < mins.z)
			softCollide(Vec3.ez, mins.z - mpos.z, softHitRadius);
		if (mpos.x > maxs.x)
			softCollide(-Vec3.ex, mpos.x - maxs.x, softHitRadius);
		if (mpos.y > maxs.y)
			softCollide(-Vec3.ey, mpos.y - maxs.y, softHitRadius);
		if (mpos.z > maxs.z)
			softCollide(-Vec3.ez, mpos.z - maxs.z, softHitRadius);
		marimo.update();

		final map = g.defaultUniformMap;
		g.withShader(copyShader, () -> ppos.render(() -> {
			g.clear(0);
			g.texture(pos.data[0]);
			g.fullScreenRect();
			g.texture(null);
		}));
		g.withShader(updatePosShader, () -> {
			setMap();
			pos.render();
		});
		g.withShader(solveShader, () -> {
			for (i in 0...2) {
				setMap();
				map.set(SolveShader.u.mode, Int(2));
				pos.render();
				setMap();
				map.set(SolveShader.u.mode, Int(3));
				pos.render();
				setMap();
				map.set(SolveShader.u.mode, Int(0));
				pos.render();
				setMap();
				map.set(SolveShader.u.mode, Int(1));
				pos.render();
			}
		});
		g.withShader(updateVelShader, () -> {
			setMap();
			map.set(UpdateVelShader.u.gravity, Vec3(0, -GRAVITY * (gravity ? 1 : 0), 0));
			this.vel.render();
		});
	}

	override function draw():Void {
		g.screen(pot.width, pot.height);
		final camPos = Vec3.of(0, 10, 0);
		final camDiff = Vec3.of(0, 30, 40);
		final shift = Math.sin(shakeCount) * shake * (shakeCount / 10);
		if (shakeCount > 0)
			shakeCount--;
		g.camera(camPos + camDiff + shift, camPos + shift, Vec3.ey);
		final rootColorAngle = Vec3.of(-1 / 3.0, 0, 1 / 3.0) - frameCount / 60 * 0.8;
		final TWO_PI = 6.283185307179586;
		g.inScene(() -> {
			g.clear(0.6 * brightness);
			g.lights();

			g.pushMatrix();
			g.color(brightness);
			g.translate(0, -0.2, 0);
			g.rotateX(1.5707963267948965);
			g.rect(-30, -30, 60, 60);
			g.popMatrix();
			g.noLights();

			g.pushMatrix();
			if (rgbMode) {
				g.color((rootColorAngle * TWO_PI).map(Math.sin) * 0.5 + 0.5);
			} else {
				g.color((color1 + (color2 - color1) * 0.2));
			}
			g.translate(marimo.pos);
			g.transform(marimo.rot);
			g.sphere(marimo.radius);
			g.popMatrix();

			g.pushMatrix();
			g.translate(marimo.pos.x, -0.1, marimo.pos.z);
			g.rotateX(1.5707963267948965);
			final effectiveRadius = marimo.radius + hairLength * (0.5 + hairVolume * 0.5);
			final s = effectiveRadius * 1.8;
			g.texture(shadow);
			final alphaCoeff = clamp(1 - (marimo.pos.y - effectiveRadius) * 0.1, 0, 1);
			if (rgbMode) {
				inline function linearStep(a:Float, edge0:Float, edge1:Float):Float {
					return (a - edge0) / (edge1 - edge0);
				}
				final amount = linearStep(numHairs, 0.2 * maxHairs, maxHairs) * 0.8;
				final length = linearStep(hairLength, 1, 10);
				final size = linearStep(marimo.radius, 1, 10);
				final coeff = 1 - size * size * (1 - length) * (1 - amount);
				g.color(((rootColorAngle + 0.5 * coeff) * TWO_PI).map(Math.sin) * 0.5 + 0.5,
					alphaCoeff * (1 - brightness));
			} else {
				g.color(0, 0.8 * alphaCoeff * brightness);
			}
			g.depthMask(false);
			g.blend(rgbMode ? Add : Normal);
			g.rect(-s, -s, s * 2, s * 2);
			g.blend(None);
			g.depthMask(true);
			g.texture(null);
			g.popMatrix();
			setMap();
			g.defaultUniformMap.set(RenderShader.u.posTex, Sampler(pos.data[0]));
			g.defaultUniformMap.set(RenderShader.u.color1, Vec3(color1.x, color1.y, color1.z));
			g.defaultUniformMap.set(RenderShader.u.color2, Vec3(color2.x, color2.y, color2.z));
			g.defaultUniformMap.set(RenderShader.u.rgb, Bool(rgbMode));
			g.withShader(renderShader, () -> {
				g.drawObjectInstanced(obj, numHairs);
			});
		});
		// debugDraw();
	}

	function debugDraw():Void {
		g.resetCamera();
		g.disableDepthTest();
		g.withShader(colorShader, () -> g.inScene(() -> {
			g.texture(ppos.data[0]);
			g.rect(0, 0, 200, 200);
			g.texture(pos.data[0]);
			g.rect(200, 0, 200, 200);
		}));
		g.enableDepthTest();
	}

	static function main():Void {
		new Main(cast Browser.document.getElementById("canvas"));
	}
}
