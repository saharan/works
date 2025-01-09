import js.Syntax;
import js.html.Element;
import js.html.InputElement;
import Shaders;
import haxe.Timer;
import js.Browser;
import js.Lib;
import js.lib.Float32Array;
import js.lib.Float64Array;
import js.lib.Int32Array;
import js.lib.Int8Array;
import js.lib.WebAssembly;
import js.lib.webassembly.Memory;
import muun.la.Mat3;
import muun.la.Vec2;
import muun.la.Vec3;
import pot.core.App;
import pot.graphics.gl.Graphics;
import pot.graphics.gl.Object;
import pot.graphics.gl.RenderTexture;
import pot.graphics.gl.Shader;
import pot.graphics.gl.Texture;
import pot.util.ImageLoader;

typedef WasmLogic = {
	clear:() -> Void,
	addParticle:(x:Float, y:Float, z:Float, vx:Float, vy:Float, vz:Float) -> Void,
	particles:() -> Int,
	updateNeighbors:() -> Void,
	preStep:(substeps:Int) -> Void,
	postStep:(substeps:Int) -> Void,
	substep:(k:Float, k2:Float, gamma:Float, c:Float, n0:Float) -> Void,
	mcTable:() -> Int,
	cellWeights:() -> Int,
	updateMesh:(threshold:Float, n0:Float, updateDensity:Bool) -> Void,
	meshVertices:() -> Int,
	numMeshTris:() -> Int,
	numMeshVerts:() -> Int,
	meshTris:() -> Int,
	debug:() -> Int,
	memory:Memory,
}

enum SceneKind {
	Cube;
	Rod;
	Collision;
	Collision2;
	Satellites;
	Torus;
	Flows;
}

class Main extends App {
	var g:Graphics;
	final ps:Array<Particle> = [];
	final ns:Array<Neighbor> = [];
	var numN:Int = 0;

	public static inline final INTERVAL = 0.3;
	public static inline final RE_RATIO = 2.1;
	public static inline final INV_RE_RATIO = 1 / RE_RATIO;
	public static inline final RE = INTERVAL * RE_RATIO;
	public static inline final INV_RE = 1 / RE;
	public static inline final RE2 = RE * RE;
	public static inline final RE_FATTEN_SCALE = 1.2;
	public static inline final RE2_FAT = RE2 * RE_FATTEN_SCALE * RE_FATTEN_SCALE;

	var wasm:WasmLogic;

	final tmpBuffer = new Float32Array(0xffffff);

	static inline final BUFFER_STRIDE = 11;

	var n0:Float = 0;

	final info = Browser.document.getElementById("info");

	override function setup():Void {
		g = new Graphics(canvas);
		g.init3D();
		pot.frameRate(Fixed(60));
		Browser.window.fetch("a.wasm").then(res -> WebAssembly.instantiateStreaming(res, {
			final obj:Dynamic = {};
			Syntax.code("{0}[\"env\"] = {1}", obj, {
				abort: function(messagePtr:Int, fileName:Int, lineNumber:Int, columnNumber:Int) {
					trace("abort: " + lineNumber + ":" + columnNumber);
					trace("offset: " + wasm.debug());
					final buffer = new Int32Array(wasm.memory.buffer, wasm.debug(), 1024 >> 2);
					trace("debug data: " + buffer.join(", "));
				}
			});
			obj;
		}).then((res) -> {
			trace("WASM loaded!");
			trace("exports: " + res.instance.exports);
			final exports = res.instance.exports;
			wasm = cast {
			};

			// protect functions from closure compiler
			Syntax.code("{0}.clear = {1}[\"clear\"];", wasm, exports);
			Syntax.code("{0}.addParticle = {1}[\"addParticle\"];", wasm, exports);
			Syntax.code("{0}.particles = {1}[\"particles\"];", wasm, exports);
			Syntax.code("{0}.updateNeighbors = {1}[\"updateNeighbors\"];", wasm, exports);
			Syntax.code("{0}.preStep = {1}[\"preStep\"];", wasm, exports);
			Syntax.code("{0}.postStep = {1}[\"postStep\"];", wasm, exports);
			Syntax.code("{0}.substep = {1}[\"substep\"];", wasm, exports);
			Syntax.code("{0}.mcTable = {1}[\"mcTable\"];", wasm, exports);
			Syntax.code("{0}.cellWeights = {1}[\"cellWeights\"];", wasm, exports);
			Syntax.code("{0}.updateMesh = {1}[\"updateMesh\"];", wasm, exports);
			Syntax.code("{0}.meshVertices = {1}[\"meshVertices\"];", wasm, exports);
			Syntax.code("{0}.numMeshTris = {1}[\"numMeshTris\"];", wasm, exports);
			Syntax.code("{0}.numMeshVerts = {1}[\"numMeshVerts\"];", wasm, exports);
			Syntax.code("{0}.meshTris = {1}[\"meshTris\"];", wasm, exports);
			Syntax.code("{0}.debug = {1}[\"debug\"];", wasm, exports);
			Syntax.code("{0}.memory = {1}[\"memory\"];", wasm, exports);

			ImageLoader.loadImages(["env.jpg", "spectrum.png"], bmps -> {
				texEnv = g.loadBitmap(bmps[0]);
				texSpectrum = g.loadBitmap(bmps[1]);
				texSpectrum.filter(Linear);
				texSpectrum.wrap(Clamp, Clamp);
				g.defaultUniformMap.set(BaseShader.u.env, Sampler(texEnv));
				g.defaultUniformMap.set(BaseShader.u.spectrum, Sampler(texSpectrum));
				initShaders();
				initTextures();
				initObjects();
				init();
				pot.start();
			});
		}));
	}

	static inline final MAX_PARTICLES = 4096;

	function init():Void {
		computeN0();
		setupUI();
		setupTable();
		initScene(Cube);
	}

	function setupUI():Void {
		inline function getById(id:String):Element {
			return Browser.document.getElementById(id);
		}
		inline function getInput(id:String):InputElement {
			return cast getById(id);
		}
		final reset = getById("reset");
		final scene = getInput("scene");
		reset.onclick = function() {
			switch scene.value {
				case "cube":
					initScene(Cube);
				case "rod":
					initScene(Rod);
				case "collision":
					initScene(Collision);
				case "collision2":
					initScene(Collision2);
				case "satellites":
					initScene(Satellites);
				case "torus":
					initScene(Torus);
				case "flows":
					initScene(Flows);
			}
		}
		scene.onchange = reset.onclick;
		final zoom = getInput("zoom");
		zoom.oninput = function() {
			zoomLevelTarget = zoom.valueAsNumber;
		}
		final strength = getInput("strength");
		strength.oninput = function() {
			this.strength = clamp(0.1 + 0.9 * strength.valueAsNumber * strength.valueAsNumber, 0.1, 1);
		}
		final pause = getInput("pause");
		pause.onchange = function() {
			paused = pause.checked;
		}
		final gravity = getInput("gravity");
		final central = getInput("central");
		gravity.onchange = function() {
			this.gravity = gravity.checked;
			central.disabled = !gravity.checked;
		}
		central.onchange = function() {
			gravityCentral = central.checked;
		}
		final causticsLow = getInput("low");
		final causticsMedium = getInput("medium");
		final causticsHigh = getInput("high");
		causticsLow.onchange = function() {
			causticsRes = CAUSTICS_RES_LOW;
			initCaustics();
		}
		causticsMedium.onchange = function() {
			causticsRes = CAUSTICS_RES_MEDIUM;
			initCaustics();
		}
		causticsHigh.onchange = function() {
			causticsRes = CAUSTICS_RES_HIGH;
			initCaustics();
		}

		syncUI = function() {
			zoom.valueAsNumber = zoomLevelTarget;
			strength.valueAsNumber = Math.sqrt((this.strength - 0.1) / 0.9);
			pause.checked = paused;
			gravity.checked = this.gravity;
			central.checked = gravityCentral;
			central.disabled = !this.gravity;
		}
	}

	function initScene(kind:SceneKind):Void {
		updateCaustics = true;
		gravity = false;
		gravityCentral = false;
		boundary = true;
		inflows.clear();
		ps.clear();
		switch (kind) {
			case Cube:
				placeBox(14, 14, 14, 0, 0, 0);
			case Rod:
				placeBox(48, 7, 7, 0, 0, 0);
			case Collision:
				placeSphere(13, -5.5, 0, 0, 0.15, 0, 0);
				placeSphere(13, 5.5, 0, 0, -0.15, 0, 0);
			case Collision2:
				placeSphere(13, -5.5, 0, -0.75, 0.15, 0, 0);
				placeSphere(13, 5.5, 0, 0.75, -0.15, 0, 0);
			case Satellites:
				gravity = true;
				gravityCentral = true;
				placeBox(12, 12, 12, 0, 0, 0, 0);
				for (p in ps) {
					p.vel <<= Vec3.of(p.pos.z, 0, -p.pos.x) * 0.1;
				}
				placeSphere(6, -6, 0, 0, 0, 0, 0.1);
				placeSphere(6, 6, 0, 0, 0, 0, -0.1);
				placeSphere(6, 0, 0, -6, 0, 0.1, 0);
				placeSphere(6, 0, 0, 6, 0, -0.1, 0);
				placeSphere(6, 0, -6, 0, 0.1, 0, 0);
				placeSphere(6, 0, 6, 0, -0.1, 0, 0);
			case Torus:
				final r = 5;
				final thickness = 0.8;
				placeBox(48, 16, 48, 0, 0, 0, 0, 0, 0, (x, y, z) -> {
					final d = Math.sqrt(x * x + z * z) - r;
					return d * d + y * y < thickness * thickness;
				});
			case Flows:
				gravity = true;
				gravityCentral = false;
				boundary = false;
				inflows.push(new Inflow(-6, 7, 0, Vec3.ex, Vec3.ez, -Vec3.ey, 2, 0.05));
				inflows.push(new Inflow(-3, 7, 0, Vec3.ex, Vec3.ez, -Vec3.ey, 2, 0.1));
				inflows.push(new Inflow(-0, 7, 0, Vec3.ex, Vec3.ez, -Vec3.ey, 2, 0.2));
				inflows.push(new Inflow(3, 7, 0, Vec3.ex, Vec3.ez, -Vec3.ey, 2, 0.3));
				inflows.push(new Inflow(6, 7, 0, Vec3.ex, Vec3.ez, -Vec3.ey, 2, 0.39));
		}
		if (syncUI != null) {
			syncUI();
		}
	}

	function placeBox(nw:Int, nh:Int, nd:Int, x:Float, y:Float, z:Float, vx:Float = 0, vy:Float = 0, vz:Float = 0,
			pred:(x:Float, y:Float, z:Float) -> Bool = null):Void {
		final center = Vec3.of(x, y, z);
		final vel = Vec3.of(vx, vy, vz);
		for (i in 0...nw) {
			for (j in 0...nh) {
				for (k in 0...nd) {
					final pos = center + Vec3.of(i - (nw - 1) * 0.5, j - (nh - 1) * 0.5, k - (nd - 1) * 0.5) * INTERVAL;
					if (pred != null && !pred(pos.x, pos.y, pos.z)) {
						continue;
					}
					final p = new Particle(pos.x, pos.y, pos.z);
					p.vel <<= vel;
					ps.push(p);
				}
			}
		}
	}

	function placeSphere(n:Int, x:Float, y:Float, z:Float, vx:Float = 0, vy:Float = 0, vz:Float = 0):Void {
		final center = Vec3.of(x, y, z);
		final vel = Vec3.of(vx, vy, vz);
		for (i in 0...n) {
			for (j in 0...n) {
				for (k in 0...n) {
					final diff = Vec3.of(i - (n - 1) * 0.5, j - (n - 1) * 0.5, k - (n - 1) * 0.5) * INTERVAL;
					final pos = center + diff;
					if (diff.length < n * INTERVAL * 0.5) {
						final p = new Particle(pos.x, pos.y, pos.z);
						p.vel <<= vel;
						ps.push(p);
					}
				}
			}
		}
	}

	function computeN0():Void {
		final m = Math.ceil(RE_RATIO);
		n0 = 0;
		for (i in -m...m + 1) {
			for (j in -m...m + 1) {
				for (k in -m...m + 1) {
					if (i == 0 && j == 0 && k == 0) {
						continue;
					}
					final pos = Vec3.of(i, j, k) * INTERVAL;
					final r = pos.length;
					if (r < RE) {
						final w = 1 - r * INV_RE;
						n0 += w * w;
					}
				}
			}
		}
		trace("n0: " + n0);
	}

	function setupTable():Void {
		final buf = new Int32Array(wasm.memory.buffer, wasm.mcTable(), 256 * 4);
		for (i in 0...meshTris.length) {
			buf[i] = meshTris[i];
		}
	}

	var texEnv:Texture;
	var texSpectrum:Texture;
	var texBack:Texture;
	var texFront:Texture;
	var texLightBack:Texture;
	var texLightFront:Texture;
	var texCaustics:RenderTexture;
	var shaderDepth:Shader;
	var shaderMain:Shader;
	var shaderCaustics:Shader;
	var shaderBlur:Shader;
	var causticsObj:Object;

	var camRotY:Float = 0;
	var camRotX:Float = PI / 6;
	var camRotTargetY:Float = 0;
	var camRotTargetX:Float = PI / 6;
	final camPos:Vec3 = Vec3.zero;
	final camTarget:Vec3 = Vec3.zero;
	final inputRayDir:Vec3 = Vec3.zero;
	var gravity:Bool = true;
	var gravityCentral:Bool = false;
	var boundary:Bool = false;
	final inflows:Array<Inflow> = [];
	var grabbing:Bool = false;
	var grabDist:Float = 0;
	var brushSize:Float = 1;
	var zoomLevel:Float = 0;
	var zoomLevelTarget:Float = 0;
	var strength:Float = 0.244;
	var paused:Bool = false;
	var syncUI:() -> Void = null;
	var updateCaustics:Bool = false;

	static inline final CAUSTICS_RES_LOW = 128;
	static inline final CAUSTICS_RES_MEDIUM = 256;
	static inline final CAUSTICS_RES_HIGH = 512;

	var causticsRes:Int = CAUSTICS_RES_MEDIUM;

	static inline final LIGHT_POS_Y = 32;
	static inline final LIGHT_SIZE = 16;
	static inline final GROUND_Y = -7.2;
	static inline final MAX_VELOCITY = 2;
	static inline final MAX_VELOCITY2 = MAX_VELOCITY * MAX_VELOCITY;

	function initObjects():Void {
		obj = g.createObject();
		causticsObj = g.createObject();
		initCaustics();
	}

	function initCaustics():Void {
		updateCaustics = true;
		final w = causticsObj.writer;
		w.clear();
		causticsObj.mode = Points;
		for (i in 0...causticsRes) {
			for (j in 0...causticsRes) {
				final u = (i + 0.5) / causticsRes;
				final v = (j + 0.5) / causticsRes;
				w.texCoord(u, v);
				final x = (u - 0.5) * LIGHT_SIZE;
				final y = (v - 0.5) * LIGHT_SIZE;
				w.vertex(x, y, 0);
				w.vertex(x, y, 0.3);
				w.vertex(x, y, 0.6);
			}
		}
		w.upload();
		causticsObj.material.shader = shaderCaustics;

		if (texLightBack != null)
			texLightBack.dispose();
		if (texLightFront != null)
			texLightFront.dispose();
		if (texCaustics != null)
			texCaustics.dispose();
		texLightBack = g.createTexture(causticsRes, causticsRes, RGBA, Float16);
		texLightFront = g.createTexture(causticsRes, causticsRes, RGBA, Float16);
		texLightBack.filter(Nearest);
		texLightFront.filter(Nearest);
		g.defaultUniformMap.set(BaseShader.u.lightBack, Sampler(texLightBack));
		g.defaultUniformMap.set(BaseShader.u.lightFront, Sampler(texLightFront));
		texCaustics = new RenderTexture(g, causticsRes, causticsRes, RGBA, Float16, 1, Linear);
	}

	function initShaders():Void {
		shaderDepth = g.createShader(DepthShader.vertexSource, DepthShader.fragmentSource);
		shaderMain = g.createShader(MainShader.vertexSource, MainShader.fragmentSource);
		shaderCaustics = g.createShader(CausticsShader.vertexSource, CausticsShader.fragmentSource);
		shaderBlur = g.createShader(BlurShader.vertexSource, BlurShader.fragmentSource);
		g.defaultUniformMap.set(CausticsShader.u.lightCameraY, Float(LIGHT_POS_Y));
		g.defaultUniformMap.set(BaseShader.u.groundY, Float(GROUND_Y));
		g.defaultUniformMap.set(BaseShader.u.groundSize, Float(LIGHT_SIZE));
	}

	function initTextures():Void {
		final w = canvas.width;
		final h = canvas.height;
		if (texBack != null)
			texBack.dispose();
		if (texFront != null)
			texFront.dispose();
		texBack = g.createTexture(w, h, RGBA, Float16);
		texFront = g.createTexture(w, h, RGBA, Float16);
		texBack.filter(Nearest);
		texFront.filter(Nearest);
		g.defaultUniformMap.set(BaseShader.u.back, Sampler(texBack));
		g.defaultUniformMap.set(BaseShader.u.front, Sampler(texFront));
	}

	var obj:Object;

	override function resized() {
		initTextures();
	}

	function updateInput():Void {
		if (input.keyboard.key(Digit1).ddown == 1) {
			initScene(Cube);
		}
		if (input.keyboard.key(Digit2).ddown == 1) {
			initScene(Rod);
		}
		if (input.keyboard.key(Digit3).ddown == 1) {
			initScene(Collision);
		}
		if (input.keyboard.key(Digit4).ddown == 1) {
			initScene(Collision2);
		}
		if (input.keyboard.key(Digit5).ddown == 1) {
			initScene(Satellites);
		}
		if (input.keyboard.key(Digit6).ddown == 1) {
			initScene(Torus);
		}
		if (input.keyboard.key(Digit7).ddown == 1) {
			initScene(Flows);
		}
		if (input.mouse.wheelY != 0) {
			zoomLevelTarget -= input.mouse.wheelY * 0.005;
			zoomLevelTarget = clamp(zoomLevelTarget, -1, 2);
			syncUI();
		}
		zoomLevel += (zoomLevelTarget - zoomLevel) * 0.3;

		final renderScale = Math.pow(2, -zoomLevel);
		final targetY = GROUND_Y / (1 + renderScale);
		camPos <<= Mat3.rot(camRotY, Vec3.ey) * (Mat3.rot(-camRotX, Vec3.ex) * Vec3.of(0, 0, 18 * renderScale)) +
			Vec3.ey * targetY;
		camTarget <<= targetY * Vec3.ey;
		g.camera(camPos, camTarget, Vec3.ey);

		final pointer = input.pointer;
		final scale = min(pot.width, pot.height);
		final dx = pointer.dx / scale;
		final dy = pointer.dy / scale;
		final down = pointer.down;
		final screen = Vec2.of(pointer.x / pot.width * 2 - 1, 1 - 2 * pointer.y / pot.height).extend(0);

		inputRayDir <<= (g.screenToWorld(screen) - camPos).normalized;
		if (!down) {
			for (p in ps) {
				p.grabbed = false;
			}
			grabbing = false;
		}
		if (pointer.ddown == 1 && !paused) {
			final dists = [];
			for (p in ps) {
				final d = p.pos - camPos;
				final b = d.dot(inputRayDir);
				final dist2 = d.lengthSq - b * b;
				if (dist2 < brushSize * brushSize) {
					p.grabbed = true;
					dists.push(b);
				}
			}
			dists.sort(Reflect.compare);
			final median = dists[dists.length >> 1];
			grabbing = false;
			grabDist = 0;
			var grabCount = 0;
			// ungrab particles that are too far
			for (p in ps) {
				if (p.grabbed) {
					final d = p.pos - camPos;
					final b = d.dot(inputRayDir);
					if (abs(b - median) > brushSize) {
						p.grabbed = false;
					} else {
						grabDist += b;
						grabCount++;
						grabbing = true;
					}
				}
			}
			if (grabbing) {
				grabDist /= grabCount;
			}
		}
		if (down) {
			if (grabbing) {
				// will be processed in integrateTime
			} else {
				camRotTargetY -= dx * 4.0;
				camRotTargetX += dy * 4.0;
				camRotTargetX = clamp(camRotTargetX, 0.01, PI / 2 - 0.01);
			}
		}
		camRotY += (camRotTargetY - camRotY) * 0.2;
		camRotX += (camRotTargetX - camRotX) * 0.2;
	}

	override function update():Void {
		// contouring threshold
		final threshold = 0.75;

		updateInput();

		final substeps = 4;

		if (!paused) {
			updateCaustics = true;
			for (inflow in inflows) {
				inflow.update(substeps, p -> {
					if (ps.length < MAX_PARTICLES)
						ps.push(p);
				});
			}
		}

		final k = 0.01 * strength; // pressure
		final k2 = 0.01 * strength; // sharp pressure
		final gamma = 0.01 * strength; // surface tension
		final c = 0.1 * strength; // viscosity

		final js = false; // true to realize how powerful SIMD is
		var st;

		// update neighbors
		st = Timer.stamp();
		updateNeighbors(js);
		final timeNeighbors = Timer.stamp() - st;

		// step the simulation
		st = Timer.stamp();
		if (!paused) {
			step(js, substeps, k, k2, gamma, c);
		}
		final timeStep = Timer.stamp() - st;

		// update mesh
		st = Timer.stamp();
		final objw = obj.writer;
		obj.mode = Triangles;
		objw.clear();
		objw.color(1);
		if (js) {
			updateMesh(threshold, paused);
			for (i in 0...verts.length) {
				objw.normal(norms[i]);
				objw.vertex(verts[i], false);
			}
			for (tri in tris) {
				objw.index(tri[0]);
				objw.index(tri[1]);
				objw.index(tri[2]);
			}
		} else {
			wasm.updateMesh(threshold, n0, paused);
			final numTris = wasm.numMeshTris();
			final numVerts = wasm.numMeshVerts();
			final ts = new Int32Array(wasm.memory.buffer, wasm.meshTris(), numTris * 3);
			final vs = new Float32Array(wasm.memory.buffer, wasm.meshVertices(), numVerts * 6);
			for (i in 0...numVerts) {
				objw.normal(Vec3.of(vs[i * 6 + 3], vs[i * 6 + 4], vs[i * 6 + 5]));
				objw.vertex(Vec3.of(vs[i * 6 + 0], vs[i * 6 + 1], vs[i * 6 + 2]), false);
			}
			for (i in 0...numTris) {
				objw.index(ts[i * 3 + 0]);
				objw.index(ts[i * 3 + 1]);
				objw.index(ts[i * 3 + 2]);
			}
		}
		objw.upload();
		final timeMesh = Timer.stamp() - st;

		if (info != null) {
			info.innerHTML = [
				"particles: " + ps.length,
				"update neighbors: " + Math.round(timeNeighbors * 1000 * 1000) / 1000 + "ms",
				"step: " + Math.round(timeStep * 1000 * 1000) / 1000 + "ms",
				"update mesh: " + Math.round(timeMesh * 1000 * 1000) / 1000 + "ms"
			].join("<br>");
		}
	}

	override function draw():Void {
		final debugView = false;

		if (debugView) {
			final drawParticles = true;
			final drawMesh = false;

			g.screen(pot.width, pot.height);
			g.camera(camPos, camTarget, Vec3.ey);

			g.inScene(() -> {
				g.clear(0, 0, 0);
				if (drawParticles) {
					g.shaping(Lines, () -> {
						final s = 0.05;
						for (p in ps) {
							final density = 1 + (p.density / n0 - 1.05) * 3;
							g.color(0.5 - density, 1 - density, 1);
							g.vertex(p.pos - Vec3.ex * s);
							g.vertex(p.pos + Vec3.ex * s);
							g.vertex(p.pos - Vec3.ey * s);
							g.vertex(p.pos + Vec3.ey * s);
							g.vertex(p.pos - Vec3.ez * s);
							g.vertex(p.pos + Vec3.ez * s);
							g.vertex(p.pos);
							g.vertex(p.pos + p.vel);
							g.color(0, 1, 0);
							g.vertex(p.pos);
							g.vertex(p.pos + p.n * 2 * s);
						}
					});
				}
				if (drawMesh) {
					g.lights();
					g.drawObject(obj);
				}
			});
			return;
		}

		if (updateCaustics) {
			// to avoid flickering
			updateCaustics = false;

			// render from light
			g.orthographic();
			g.screen(LIGHT_SIZE, LIGHT_SIZE);
			g.camera(Vec3.of(0, LIGHT_POS_Y, 0), Vec3.zero, -Vec3.ez);
			final iv = g.getViewMatrix().inv;
			// precompute since slow
			g.defaultUniformMap.set(BaseShader.u.invLightView, Mat(4, 4, [
				iv.e00, iv.e10, iv.e20, iv.e30,
				iv.e01, iv.e11, iv.e21, iv.e31,
				iv.e02, iv.e12, iv.e22, iv.e32,
				iv.e03, iv.e13, iv.e23, iv.e33
			]));
			// render depths for refraction
			g.withShader(shaderDepth, () -> {
				g.blend(None);
				g.renderingTo(texLightBack.frameBuffer, () -> g.inScene(() -> {
					g.clear(0, 0, 0, 0);
					g.culling(Front);
					g.drawObject(obj);
				}));
				g.renderingTo(texLightFront.frameBuffer, () -> g.inScene(() -> {
					g.clear(0, 0, 0, 0);
					g.culling(Back);
					g.drawObject(obj);
				}));
				g.blend();
			});
			// render photons
			g.defaultUniformMap.set(BaseShader.u.time, Float(frameCount / 60));
			texCaustics.render(() -> {
				g.clear(0, 0, 0, 1);
				g.disableDepthTest();
				g.blend(Add);
				g.drawObject(causticsObj);
				g.enableDepthTest();
				g.blend();
			});
			// blur a bit
			g.defaultUniformMap.set(BaseShader.u.caustics, Sampler(texCaustics.data[0]));
			texCaustics.render(() -> {
				g.clear(0);
				g.withShader(shaderBlur, () -> g.withTexture(texCaustics.data[0], () -> {
					g.fullScreenRect();
				}));
			});
		}
		g.defaultUniformMap.set(BaseShader.u.caustics, Sampler(texCaustics.data[0]));

		g.perspective(PI / 3, FovMin);
		g.screen(pot.width, pot.height);
		g.camera(camPos, camTarget, Vec3.ey);

		// render depths for reflection and refraction
		g.withShader(shaderDepth, () -> {
			g.blend(None);
			g.renderingTo(texBack.frameBuffer, () -> g.inScene(() -> {
				g.clear(0, 0, 0, 0);
				g.culling(Front);
				g.drawObject(obj);
			}));
			g.renderingTo(texFront.frameBuffer, () -> g.inScene(() -> {
				g.clear(0, 0, 0, 0);
				g.culling(Back);
				g.drawObject(obj);
			}));
			g.blend();
		});

		g.inScene(() -> {
			g.clear(0, 0, 0);
			g.withShader(shaderMain, () -> {
				g.fullScreenRect();
			});
		});
	}

	function updateNeighbors(js:Bool):Void {
		if (js) {
			// O(N^2), SLOW
			numN = 0;
			final n = ps.length;
			var numActualN = 0;
			for (i in 0...n) {
				final p1 = ps[i];
				for (j in 0...i) {
					final p2 = ps[j];
					final d = p1.pos - p2.pos;
					final r2 = d.lengthSq;
					if (r2 < RE2_FAT) {
						final r = Math.sqrt(r2);
						if (ns.length == numN) {
							ns.push(new Neighbor());
						}
						final nb = ns[numN++];
						nb.init(p1, p2);
						if (r2 < RE2) {
							numActualN++;
						}
					}
				}
			}
			trace("number of speculative neighbors: " + (numN - numActualN) + " (" + (numN - numActualN) / numN * 100 +
				"%)");
		} else {
			// spatial hashing, O(N)
			wasm.clear();
			for (p in ps) {
				wasm.addParticle(p.pos.x, p.pos.y, p.pos.z, p.vel.x, p.vel.y, p.vel.z);
			}
			wasm.updateNeighbors();
		}
	}

	function integrateTime(mem:Float32Array, substeps:Int):Void {
		final down = input.pointer.down;
		final ss2 = substeps * substeps;
		final damp = Math.pow(0.9, 1 / substeps);
		final grabTarget = camPos + inputRayDir * grabDist;
		final boundSide = 7;
		final boundTopBottom = 7;
		for (p in ps) {
			final idx = p.index * BUFFER_STRIDE;
			final pos = Vec3.of(mem[idx + 0], mem[idx + 1], mem[idx + 2]);
			final vel = Vec3.of(mem[idx + 3], mem[idx + 4], mem[idx + 5]);
			if (vel.lengthSq > MAX_VELOCITY2) {
				vel <<= vel.normalized * MAX_VELOCITY;
			}
			if (p.kinematicFor != 0) {
				vel <<= p.kinematicVel / substeps;
				pos += vel;
				if (p.kinematicFor > 0)
					p.kinematicFor--;
			} else {
				pos += vel;
				if (gravity) {
					if (gravityCentral) {
						vel -= pos.normalized * 0.002 / ss2;
					} else {
						vel.y -= 0.01 / ss2;
					}
				}
				if (p.grabbed) {
					vel *= damp;
					final dist = (pos - grabTarget).length;
					final coeff = 0.25 / (1 + brushSize * 0.5) * min(1, dist / (brushSize * 2)) / ss2;
					vel += (grabTarget - pos) * coeff;
				}
				if (boundary) {
					if (pos.x < -boundSide) {
						if (vel.x < 0)
							vel.x = 0;
						pos.x = -boundSide;
					}
					if (pos.x > boundSide) {
						if (vel.x > 0)
							vel.x = 0;
						pos.x = boundSide;
					}
					if (pos.y < -boundTopBottom) {
						if (vel.y < 0)
							vel.y = 0;
						pos.y = -boundTopBottom;
					}
					if (pos.y > boundTopBottom) {
						if (vel.y > 0)
							vel.y = 0;
						pos.y = boundTopBottom;
					}
					if (pos.z < -boundSide) {
						if (vel.z < 0)
							vel.z = 0;
						pos.z = -boundSide;
					}
					if (pos.z > boundSide) {
						if (vel.z > 0)
							vel.z = 0;
						pos.z = boundSide;
					}
				} else {
					if (pos.x < -boundSide || pos.x > boundSide || pos.y < -boundTopBottom || pos.y > boundTopBottom || pos.z < -boundSide || pos.z > boundSide) {
						p.remove = true;
					}
				}
			}
			mem[idx + 0] = pos.x;
			mem[idx + 1] = pos.y;
			mem[idx + 2] = pos.z;
			mem[idx + 3] = vel.x;
			mem[idx + 4] = vel.y;
			mem[idx + 5] = vel.z;
		}
	}

	function step(js:Bool, substeps:Int, k:Float, k2:Float, gamma:Float, c:Float):Void {
		final numP = ps.length;
		for (i in 0...numP) {
			ps[i].index = i;
		}
		if (js) {
			for (i in 0...numP) {
				final p = ps[i];
				final pos = p.pos;
				final vel = p.vel;
				final idx = i * BUFFER_STRIDE;
				tmpBuffer[idx + 0] = pos.x;
				tmpBuffer[idx + 1] = pos.y;
				tmpBuffer[idx + 2] = pos.z;
				tmpBuffer[idx + 3] = vel.x / substeps;
				tmpBuffer[idx + 4] = vel.y / substeps;
				tmpBuffer[idx + 5] = vel.z / substeps;
				tmpBuffer[idx + 6] = 0; // normal
				tmpBuffer[idx + 7] = 0;
				tmpBuffer[idx + 8] = 0;
				tmpBuffer[idx + 9] = 0; // density
				tmpBuffer[idx + 10] = 0; // pressure
			}
			for (i in 0...substeps) {
				for (i in 0...numP) {
					var idx = i * BUFFER_STRIDE;
					tmpBuffer[idx + 6] = 0;
					tmpBuffer[idx + 7] = 0;
					tmpBuffer[idx + 8] = 0;
					tmpBuffer[idx + 9] = 0;
				}
				for (i in 0...numN) {
					final nb = ns[i];
					final idx1 = nb.p1.index * BUFFER_STRIDE;
					final idx2 = nb.p2.index * BUFFER_STRIDE;

					final px1 = tmpBuffer[idx1 + 0];
					final py1 = tmpBuffer[idx1 + 1];
					final pz1 = tmpBuffer[idx1 + 2];
					final px2 = tmpBuffer[idx2 + 0];
					final py2 = tmpBuffer[idx2 + 1];
					final pz2 = tmpBuffer[idx2 + 2];
					final dx = px1 - px2;
					final dy = py1 - py2;
					final dz = pz1 - pz2;
					final r2 = dx * dx + dy * dy + dz * dz;

					nb.disabled = r2 >= RE2;
					if (nb.disabled)
						continue;
					final r = Math.sqrt(r2);
					nb.r = r;
					final invR = r == 0 ? 0 : 1 / r;
					final w = 1 - r * INV_RE;
					final w2 = w * w;
					nb.w = w;
					nb.w2 = w2;
					final nx = dx * invR;
					final ny = dy * invR;
					final nz = dz * invR;
					nb.n.x = nx;
					nb.n.y = ny;
					nb.n.z = nz;
					final nwx = nx * w;
					final nwy = ny * w;
					final nwz = nz * w;
					tmpBuffer[idx1 + 6] += nwx;
					tmpBuffer[idx1 + 7] += nwy;
					tmpBuffer[idx1 + 8] += nwz;
					tmpBuffer[idx1 + 9] += w2;
					tmpBuffer[idx2 + 6] -= nwx;
					tmpBuffer[idx2 + 7] -= nwy;
					tmpBuffer[idx2 + 8] -= nwz;
					tmpBuffer[idx2 + 9] += w2;
				}
				for (i in 0...numP) {
					final idx = i * BUFFER_STRIDE;
					tmpBuffer[idx + 6] *= INV_RE_RATIO;
					tmpBuffer[idx + 7] *= INV_RE_RATIO;
					tmpBuffer[idx + 8] *= INV_RE_RATIO;
					tmpBuffer[idx + 10] = k * (tmpBuffer[idx + 9] - n0);
				}
				for (i in 0...numN) {
					final nb = ns[i];
					if (nb.disabled)
						continue;
					final idx1 = nb.p1.index * BUFFER_STRIDE;
					final idx2 = nb.p2.index * BUFFER_STRIDE;
					final p1 = tmpBuffer[idx1 + 10];
					final p2 = tmpBuffer[idx2 + 10];
					final nx = nb.n.x;
					final ny = nb.n.y;
					final nz = nb.n.z;
					final w = nb.w;
					final w2 = nb.w2;
					final p = p1 + p2 + w2 * w * k2;
					final rvx = tmpBuffer[idx1 + 3] - tmpBuffer[idx2 + 3];
					final rvy = tmpBuffer[idx1 + 4] - tmpBuffer[idx2 + 4];
					final rvz = tmpBuffer[idx1 + 5] - tmpBuffer[idx2 + 5];
					final vn = nx * rvx + ny * rvy + nz * rvz;
					final rnx = tmpBuffer[idx1 + 6] - tmpBuffer[idx2 + 6];
					final rny = tmpBuffer[idx1 + 7] - tmpBuffer[idx2 + 7];
					final rnz = tmpBuffer[idx1 + 8] - tmpBuffer[idx2 + 8];
					final nCoeff = w * (p - c * vn);
					// final nCoeff = w * p;
					final rnCoeff = w * gamma;
					// final rnCoeff = 0;
					final fx = nx * nCoeff + rnx * rnCoeff;
					final fy = ny * nCoeff + rny * rnCoeff;
					final fz = nz * nCoeff + rnz * rnCoeff;
					tmpBuffer[idx1 + 3] += fx;
					tmpBuffer[idx1 + 4] += fy;
					tmpBuffer[idx1 + 5] += fz;
					tmpBuffer[idx2 + 3] -= fx;
					tmpBuffer[idx2 + 4] -= fy;
					tmpBuffer[idx2 + 5] -= fz;
				}
				integrateTime(tmpBuffer, substeps);
			}
			for (i in 0...numP) {
				final idx = i * BUFFER_STRIDE;
				final p = ps[i];
				p.pos.x = tmpBuffer[idx + 0];
				p.pos.y = tmpBuffer[idx + 1];
				p.pos.z = tmpBuffer[idx + 2];
				p.vel.x = tmpBuffer[idx + 3] * substeps;
				p.vel.y = tmpBuffer[idx + 4] * substeps;
				p.vel.z = tmpBuffer[idx + 5] * substeps;
				p.n.x = tmpBuffer[idx + 6];
				p.n.y = tmpBuffer[idx + 7];
				p.n.z = tmpBuffer[idx + 8];
				p.density = tmpBuffer[idx + 9];
				p.p = tmpBuffer[idx + 10];
			}
		} else {
			final mem = new Float32Array(wasm.memory.buffer, wasm.particles());
			wasm.preStep(substeps);
			for (i in 0...substeps) {
				wasm.substep(k, k2, gamma, c, n0);
				integrateTime(mem, substeps);
			}
			wasm.postStep(substeps);
			// download
			for (i in 0...numP) {
				final idx = i * BUFFER_STRIDE;
				final p = ps[i];
				p.pos.x = mem[idx + 0];
				p.pos.y = mem[idx + 1];
				p.pos.z = mem[idx + 2];
				p.vel.x = mem[idx + 3];
				p.vel.y = mem[idx + 4];
				p.vel.z = mem[idx + 5];
				p.n.x = mem[idx + 6];
				p.n.y = mem[idx + 7];
				p.n.z = mem[idx + 8];
				p.density = mem[idx + 9];
				p.p = mem[idx + 10];
			}
		}
		// remove particles
		var j = 0;
		for (i in 0...numP) {
			if (!ps[i].remove) {
				ps[j++] = ps[i];
			}
		}
		ps.resize(j);
	}

	// JS-side mesh generation
	static inline final MESH_RES_SHIFT = 6;
	static inline final MESH_RES_SHIFT2 = MESH_RES_SHIFT * 2;
	static inline final MESH_RES_SHIFT3 = MESH_RES_SHIFT * 3;
	static inline final MESH_RES = 1 << MESH_RES_SHIFT;
	static inline final MESH_RES_MASK = MESH_RES - 1;
	static inline final MESH_RES2 = MESH_RES * MESH_RES;
	static inline final MESH_RES3 = MESH_RES * MESH_RES * MESH_RES;
	static inline final MESH_GRID_SIZE = INTERVAL;
	static inline final INV_MESH_GRID_SIZE = 1 / MESH_GRID_SIZE;

	final meshWeights = new Float32Array(MESH_RES3);
	final meshVisited = new Int8Array(MESH_RES3);
	final edgeIndices = new Int32Array(MESH_RES3 * 3);

	// marching cubes table
	final meshTris = [0, 0, 0, 0, 17039873, 0, 0, 0, 218172161, 0, 0, 0, 218366466, 852491, 0, 0, 370344449, 0, 0, 0,
		68550914, 71187, 0, 0, 185406212, 318833165, 34999574, 13, 185406211, 369366541, 4877, 0, 320801537, 0, 0, 0,
		67244804, 319488260, 69148420, 11, 520945922, 2031891, 0, 0, 67244803, 522128644, 1043, 0, 371130882, 139019,
		0, 0, 520814851, 67376671, 7937, 0, 34996483, 220138774, 278, 0, 218373890, 1449732, 0, 0, 69543425, 0, 0, 0,
		637665538, 2490661, 0, 0, 185410820, 621019403, 187049483, 4, 185410819, 640025099, 2853, 0, 370353668,
		637666323, 69538597, 19, 370353667, 620832019, 9747, 0, 220531461, 371594789, 369824523, 33816869, 185406212,
		319628563, 370353446, 38, 623248386, 1253131, 0, 0, 520814853, 522526465, 35586579, 623255334, 637796613,
		638789121, 220597541, 320808479, 522588932, 520955167, 34809126, 38, 69534213, 623184642, 522528278,
		520824086, 622791428, 522589727, 621487398, 1, 67174916, 371533334, 219548965, 31, 520951299, 623191574, 5645,
		0, 621620993, 0, 0, 0, 67249412, 620825858, 221184559, 2, 187629826, 77605, 0, 0, 67249411, 789262082, 9474,
		0, 790957314, 1446658, 0, 0, 221184261, 791614209, 372188420, 370355972, 34996485, 370550017, 789975819,
		790959627, 789975812, 371524630, 789786405, 11, 320810756, 789383955, 321201427, 13, 621019653, 522137381,
		620888595, 218824991, 320810755, 623182099, 4911, 0, 67244804, 321192979, 789786405, 31, 621611781, 620897547,
		522526511, 35005718, 17632004, 523183391, 371139844, 4, 371524100, 371142422, 16920357, 37, 68558595,
		623846687, 1055, 0, 67970562, 2493743, 0, 0, 221184259, 36045359, 303, 0, 637796611, 185282342, 9729, 0,
		34287362, 3089922, 0, 0, 370353669, 320024358, 219349508, 221188868, 789777668, 791025199, 17634835, 19,
		16909316, 638980902, 791024395, 11, 187639299, 320213798, 2854, 0, 320810757, 321262383, 219352331, 637801220,
		184618244, 789782319, 36635155, 38, 321258500, 639577894, 319034143, 1, 637677315, 320020271, 12034, 0,
		184683780, 637799682, 371138351, 38, 371140099, 221193759, 2817, 0, 371142403, 70198806, 258, 0, 371140098,
		3089951, 0, 0, 924198401, 0, 0, 0, 17049092, 638976513, 20395777, 22, 641144322, 852235, 0, 0, 924189189,
		923481858, 70714406, 185415437, 36049666, 1254967, 0, 0, 17049091, 926356225, 294, 0, 185406213, 218969875,
		638386434, 641142018, 221711108, 218375693, 319497783, 55, 520828676, 923997707, 371591974, 11, 924781317,
		67380791, 923470593, 369234692, 371593989, 640024851, 220608287, 218179103, 320209412, 69613316, 218380063,
		31, 520828675, 637675019, 14091, 0, 520814852, 20389633, 637609527, 4, 638386436, 221716237, 637609527, 2,
		520946691, 925251332, 7940, 0, 369370370, 1451319, 0, 0, 924189187, 16852279, 14082, 0, 185410821, 188156709,
		67830785, 924191510, 188159492, 923608375, 185993997, 2, 69534211, 322376485, 549, 0, 318846722, 2438913, 0,
		0, 16909316, 621481253, 321196811, 55, 924001539, 185273637, 9491, 0, 520828677, 185279799, 67834646,
		69536534, 34805252, 924781367, 624364289, 1, 18028036, 622199809, 622802719, 13, 520955139, 371537695, 531, 0,
		621478916, 624369445, 33824523, 11, 19216131, 186583863, 311, 0, 520959747, 69547789, 258, 0, 520955138,
		2438943, 0, 0, 221198084, 925246733, 219551245, 38, 17641221, 370541057, 19869495, 69608726, 371598597,
		369169957, 789983031, 17503755, 639960068, 37164546, 788672311, 11, 221198085, 219352375, 638395941,
		318901506, 639960068, 17641217, 318844727, 55, 620832260, 318907905, 187641655, 19, 187634435, 641143599,
		9476, 0, 320218629, 218958611, 321267237, 523187981, 621028868, 371142455, 17629715, 11, 792141572, 320218643,
		18032165, 37, 320209411, 70203167, 9765, 0, 792141572, 186977547, 638264869, 2, 218824963, 70203167, 9765, 0,
		36045059, 790954278, 14111, 0, 621028866, 2043703, 0, 0, 221198083, 370541581, 3383, 0, 221198084, 922815799,
		37159425, 22, 369833732, 369361174, 792133899, 11, 187630083, 926356994, 559, 0, 319631108, 218235917,
		321852162, 55, 923992323, 789393153, 14081, 0, 187643651, 37163787, 1025, 0, 187634434, 3609391, 0, 0,
		924790532, 218829581, 67965718, 22, 218824963, 37166895, 4886, 0, 369361155, 520164118, 12087, 0, 34805250,
		2043703, 0, 0, 67961347, 520815117, 12087, 0, 184618242, 3612463, 0, 0, 523187970, 66052, 0, 0, 924790529, 0,
		0, 0, 523710209, 0, 0, 0, 925835010, 66562, 0, 0, 218181380, 789257985, 523698487, 1, 523700997, 926351883,
		70725389, 67254029, 35010308, 924783362, 36646658, 31, 790565637, 788606739, 372184631, 17051396, 372703749,
		221187383, 218235138, 186585911, 521341700, 221720333, 369956407, 4, 789254914, 3085111, 0, 0, 67244805,
		70714387, 184814337, 925828143, 218181379, 924006145, 12033, 0, 923009540, 70192388, 922892079, 19, 35010307,
		791612162, 567, 0, 70189316, 68564740, 184629039, 47, 34996484, 18233089, 218183471, 47, 68553987, 926363405,
		3350, 0, 637810436, 925183748, 790561823, 4, 790570245, 522125605, 35600166, 33627942, 67184133, 520822529,
		522598182, 789390593, 623840516, 186595083, 34289446, 38, 521350917, 67240979, 70198575, 638990099, 925242884,
		321855251, 622011695, 1, 220540676, 522589751, 33821451, 1, 521341699, 221718038, 9519, 0, 637810437,
		67375927, 184821039, 185795631, 19214084, 321850113, 321271590, 2, 623840516, 19268609, 922826534, 19,
		637670147, 789788454, 3365, 0, 925242884, 33826050, 184689967, 47, 789250307, 637609263, 5687, 0, 33816835,
		221718038, 9519, 0, 220540674, 2496055, 0, 0, 220144898, 2432823, 0, 0, 67249413, 33699621, 520225037,
		523698701, 523700995, 19202359, 2871, 0, 922885892, 925172791, 186582018, 2, 35010309, 35979831, 520232723,
		621609485, 318840580, 621616897, 68556343, 37, 319495940, 922883639, 20381954, 37, 68560131, 523707670, 4875,
		0, 621611779, 320026405, 9483, 0, 184618244, 621019685, 925172243, 19, 18036482, 3613953, 0, 0, 322381059,
		33817125, 4901, 0, 35982596, 622212901, 34406934, 11, 68564739, 221717764, 2817, 0, 620836611, 33691191,
		14081, 0, 68560130, 3613974, 0, 0, 637810435, 520953604, 14084, 0, 35600132, 520162591, 37159425, 38,
		637810436, 923009335, 523698443, 11, 637668099, 924792587, 9739, 0, 372712964, 68354564, 520363795, 13,
		220135683, 370344223, 14118, 0, 33816835, 186005286, 7955, 0, 319495938, 2496055, 0, 0, 68363780, 67963652,
		925240083, 19, 637679363, 185808642, 269, 0, 322371843, 640025601, 311, 0, 637670146, 1259302, 0, 0, 67963651,
		369820164, 14118, 0, 638990082, 721165, 0, 0, 16909314, 1455910, 0, 0, 372712961, 0, 0, 0, 521545218, 2041391,
		0, 0, 17049093, 19857702, 369169922, 790561055, 218181381, 16852527, 369167135, 371589407, 34283268,
		639571458, 638398221, 4, 790565635, 33695279, 12051, 0, 19865348, 788801071, 18809092, 19, 319495940,
		789381423, 640614658, 2, 218375683, 522596109, 4875, 0, 371593987, 187632422, 4902, 0, 34805252, 637600806,
		187042561, 47, 637605380, 640617766, 320212225, 1, 218377987, 371601156, 531, 0, 184692482, 2502402, 0, 0,
		789259779, 16843814, 9739, 0, 36056835, 17629487, 559, 0, 218375682, 2502413, 0, 0, 790570243, 68551711, 9503,
		0, 520171268, 521536031, 623837697, 1, 220540676, 520162079, 69141505, 22, 521536003, 218237727, 9519, 0,
		790570244, 622793509, 69538562, 2, 19206915, 791617299, 4901, 0, 186585859, 34415919, 1025, 0, 319495938,
		861487, 0, 0, 184820996, 68359684, 186977043, 47, 789259523, 33629451, 4886, 0, 369365763, 218174212, 9519, 0,
		789390594, 135958, 0, 0, 789250563, 621028610, 12034, 0, 789250306, 75055, 0, 0, 16909314, 3083557, 0, 0,
		220540673, 0, 0, 0, 371598595, 218963734, 5669, 0, 621028868, 369230102, 521535757, 13, 18228740, 369827606,
		19267851, 37, 521538307, 67242774, 9765, 0, 218244356, 220140301, 639963906, 2, 220140291, 68354317, 9765, 0,
		36054275, 186974466, 7955, 0, 69608706, 1248031, 0, 0, 371598596, 622007845, 186977043, 13, 369234691,
		186975270, 269, 0, 620827395, 638985747, 9491, 0, 34805250, 2425894, 0, 0, 36047619, 623185163, 2854, 0,
		184618242, 271909, 0, 0, 36045058, 2425126, 0, 0, 621028865, 0, 0, 0, 67968770, 2037252, 0, 0, 220141059,
		16908566, 3350, 0, 369368835, 16845599, 7940, 0, 521536002, 133919, 0, 0, 220136451, 320012804, 1055, 0,
		220135682, 1245471, 0, 0, 67174914, 728851, 0, 0, 521341697, 0, 0, 0, 369364227, 319492877, 5645, 0, 17632002,
		1442323, 0, 0, 369361154, 70422, 0, 0, 320209409, 0, 0, 0, 67961346, 721421, 0, 0, 17632001, 0, 0, 0,
		67174913, 0, 0, 0, 0, 0, 0, 0];

	final verts:Array<Vec3> = [];
	final norms:Array<Vec3> = [];
	final tris:Array<Array<Int>> = [];

	function updateMesh(threshold:Float, updateDensity:Bool):Void {
		if (updateDensity) {
			for (p in ps) {
				p.density = 0;
			}
			for (i in 0...numN) {
				final nb = ns[i];
				final p1 = nb.p1;
				final p2 = nb.p2;
				final dx = p1.pos.x - p2.pos.x;
				final dy = p1.pos.y - p2.pos.y;
				final dz = p1.pos.z - p2.pos.z;
				final r2 = dx * dx + dy * dy + dz * dz;
				if (r2 >= RE2)
					continue;
				final r = Math.sqrt(r2);
				final invR = r == 0 ? 0 : 1 / r;
				final w = 1 - r * INV_RE;
				final w2 = w * w;
				p1.density += w2;
				p2.density += w2;
			}
		}
		meshWeights.fill(0);
		meshVisited.fill(0);
		edgeIndices.fill(-1);
		final meshCells = [];
		final wxs = [0.0, 0.0, 0.0];
		final wys = [0.0, 0.0, 0.0];
		final wzs = [0.0, 0.0, 0.0];
		for (p in ps) {
			final pos = p.pos;
			final gx = pos.x * INV_MESH_GRID_SIZE - MESH_RES * 0.5;
			final gy = pos.y * INV_MESH_GRID_SIZE - MESH_RES * 0.5;
			final gz = pos.z * INV_MESH_GRID_SIZE - MESH_RES * 0.5;
			final igx = Math.floor(gx);
			final igy = Math.floor(gy);
			final igz = Math.floor(gz);
			// cell -> particle
			final fx = gx - igx - 0.5;
			final fy = gy - igy - 0.5;
			final fz = gz - igz - 0.5;
			final wx0 = 0.5 * (0.5 - fx) * (0.5 - fx);
			final wx1 = 0.75 - fx * fx;
			final wx2 = 0.5 * (0.5 + fx) * (0.5 + fx);
			final wy0 = 0.5 * (0.5 - fy) * (0.5 - fy);
			final wy1 = 0.75 - fy * fy;
			final wy2 = 0.5 * (0.5 + fy) * (0.5 + fy);
			final wz0 = 0.5 * (0.5 - fz) * (0.5 - fz);
			final wz1 = 0.75 - fz * fz;
			final wz2 = 0.5 * (0.5 + fz) * (0.5 + fz);
			final w = 1 + max(0, 1 - p.density / n0);
			wxs[0] = wx0 * w;
			wxs[1] = wx1 * w;
			wxs[2] = wx2 * w;
			wys[0] = wy0 * w;
			wys[1] = wy1 * w;
			wys[2] = wy2 * w;
			wzs[0] = wz0 * w;
			wzs[1] = wz1 * w;
			wzs[2] = wz2 * w;
			for (di in -1...2) {
				for (dj in -1...2) {
					for (dk in -1...2) {
						final x = igx + di & MESH_RES_MASK;
						final y = igy + dj & MESH_RES_MASK;
						final z = igz + dk & MESH_RES_MASK;
						final idx = x << MESH_RES_SHIFT2 | y << MESH_RES_SHIFT | z;
						final wx = wxs[di + 1];
						final wy = wys[dj + 1];
						final wz = wzs[dk + 1];
						meshWeights[idx] += wx * wy * wz;
						if (meshWeights[idx] >= threshold && meshVisited[idx] == 0) {
							meshVisited[idx] = 1;
							meshCells.push(idx);
						}
					}
				}
			}
		}
		{
			final size = meshCells.length;
			for (ii in 0...size) { // extend active cells to the negative direction
				final i = meshCells[ii];
				final x = i >> MESH_RES_SHIFT2 & MESH_RES_MASK;
				final y = i >> MESH_RES_SHIFT & MESH_RES_MASK;
				final z = i & MESH_RES_MASK;
				for (di in -1...1) {
					for (dj in -1...1) {
						for (dk in -1...1) {
							final x2 = x + di & MESH_RES_MASK;
							final y2 = y + dj & MESH_RES_MASK;
							final z2 = z + dk & MESH_RES_MASK;
							final idx = x2 << MESH_RES_SHIFT2 | y2 << MESH_RES_SHIFT | z2;
							if (meshVisited[idx] == 0) {
								meshVisited[idx] = 1;
								meshCells.push(idx);
							}
						}
					}
				}
			}
		}
		var cellCount = 0;
		final verts2 = []; // for smoothing
		final vweights = [];
		verts.clear();
		norms.clear();
		tris.clear();
		for (idx in meshCells) {
			final x = idx >> MESH_RES_SHIFT2 & MESH_RES_MASK;
			final y = idx >> MESH_RES_SHIFT & MESH_RES_MASK;
			final z = idx & MESH_RES_MASK;
			if (x == MESH_RES_MASK || y == MESH_RES_MASK || z == MESH_RES_MASK)
				continue;
			var bits = 0;
			var shift = 0;
			for (di in 0...2) {
				for (dj in 0...2) {
					for (dk in 0...2) {
						final x2 = x + di & MESH_RES_MASK;
						final y2 = y + dj & MESH_RES_MASK;
						final z2 = z + dk & MESH_RES_MASK;
						final idx2 = x2 << MESH_RES_SHIFT2 | y2 << MESH_RES_SHIFT | z2;
						if (meshWeights[idx2] < threshold) {
							bits |= 1 << shift;
						}
						shift++;
					}
				}
			}
			if (bits != 0 && bits != 0xff) {
				inline function interp(p1:Vec3, p2:Vec3, v1:Float, v2:Float):Int {
					final t = (threshold - v1) / (v2 - v1);
					final p = p1 + (p2 - p1) * t;
					verts.push(p);
					norms.push(Vec3.zero);
					vweights.push(0.0);
					return verts.length - 1;
				}
				inline function edge(e:Int):Int {
					final x1 = x + (e >> 5 & 1);
					final y1 = y + (e >> 4 & 1);
					final z1 = z + (e >> 3 & 1);
					final x2 = x + (e >> 2 & 1);
					final y2 = y + (e >> 1 & 1);
					final z2 = z + (e & 1);
					final dir = x1 != x2 ? 0 : y1 != y2 ? 1 : 2;
					final edgeIndex = dir << MESH_RES_SHIFT3 | x1 << MESH_RES_SHIFT2 | y1 << MESH_RES_SHIFT | z1;
					if (edgeIndices[edgeIndex] == -1) {
						final p1 = (Vec3.of(x1, y1, z1) - (MESH_RES - 1) * 0.5) * MESH_GRID_SIZE;
						final p2 = (Vec3.of(x2, y2, z2) - (MESH_RES - 1) * 0.5) * MESH_GRID_SIZE;
						final idx1 = x1 << MESH_RES_SHIFT2 | y1 << MESH_RES_SHIFT | z1;
						final idx2 = x2 << MESH_RES_SHIFT2 | y2 << MESH_RES_SHIFT | z2;
						final v1 = meshWeights[idx1];
						final v2 = meshWeights[idx2];
						edgeIndices[edgeIndex] = interp(p1, p2, v1, v2);
					}
					return edgeIndices[edgeIndex];
				}
				var idx = bits * 4;
				final t1 = meshTris[idx];
				final t2 = meshTris[idx + 1];
				final t3 = meshTris[idx + 2];
				final t4 = meshTris[idx + 3];

				final numTris = t1 & 0xff;
				final e11 = t1 >> 8 & 0xff;
				final e12 = t1 >> 16 & 0xff;
				final e13 = t1 >>> 24;
				final e21 = t2 & 0xff;
				final e22 = t2 >> 8 & 0xff;
				final e23 = t2 >> 16 & 0xff;
				final e31 = t2 >>> 24;
				final e32 = t3 & 0xff;
				final e33 = t3 >> 8 & 0xff;
				final e41 = t3 >> 16 & 0xff;
				final e42 = t3 >>> 24;
				final e43 = t4 & 0xff;
				final e51 = t4 >> 8 & 0xff;
				final e52 = t4 >> 16 & 0xff;
				final e53 = t4 >>> 24;

				do {
					if (numTris == 0)
						break;
					tris.push([edge(e11), edge(e12), edge(e13)]);
					if (numTris == 1)
						break;
					tris.push([edge(e21), edge(e22), edge(e23)]);
					if (numTris == 2)
						break;
					tris.push([edge(e31), edge(e32), edge(e33)]);
					if (numTris == 3)
						break;
					tris.push([edge(e41), edge(e42), edge(e43)]);
					if (numTris == 4)
						break;
					tris.push([edge(e51), edge(e52), edge(e53)]);
				} while (false);
				cellCount++;
			}
		}
		verts2.clear();
		for (i in 0...verts.length) {
			verts2.push(Vec3.zero);
		}
		for (i in 0...verts.length) {
			vweights[i] = 0;
		}
		// pass 1
		for (tri in tris) {
			final v1 = verts[tri[0]];
			final v2 = verts[tri[1]];
			final v3 = verts[tri[2]];
			final area = (v2 - v1).cross(v3 - v1).length;
			vweights[tri[0]] += area;
			vweights[tri[1]] += area;
			vweights[tri[2]] += area;
			verts2[tri[0]] += (v2 + v3) * area;
			verts2[tri[1]] += (v3 + v1) * area;
			verts2[tri[2]] += (v1 + v2) * area;
		}
		for (i in 0...verts.length) {
			final mean = verts2[i] / (vweights[i] * 2);
			verts2[i] <<= (verts[i] + mean) * 0.5;
			verts[i] <<= Vec3.zero;
			vweights[i] = 0;
		}
		// pass 2
		for (tri in tris) {
			final v1 = verts2[tri[0]];
			final v2 = verts2[tri[1]];
			final v3 = verts2[tri[2]];
			final area = (v2 - v1).cross(v3 - v1).length;
			vweights[tri[0]] += area;
			vweights[tri[1]] += area;
			vweights[tri[2]] += area;
			verts[tri[0]] += (v2 + v3) * area;
			verts[tri[1]] += (v3 + v1) * area;
			verts[tri[2]] += (v1 + v2) * area;
		}
		for (i in 0...verts.length) {
			final mean = verts[i] / (vweights[i] * 2);
			verts[i] <<= (verts2[i] + mean) * 0.5;
		}
		for (tri in tris) {
			final p1 = verts[tri[0]];
			final p2 = verts[tri[1]];
			final p3 = verts[tri[2]];
			final n = (p2 - p1).cross(p3 - p1);
			norms[tri[0]] += n;
			norms[tri[1]] += n;
			norms[tri[2]] += n;
		}
		// note: on the WASM side, normals are smoothed over the mesh
	}

	static function main():Void {
		new Main(cast Browser.document.getElementById("canvas"), true, true);
	}
}
