import js.Syntax;
import haxe.Timer;
import js.Browser;
import js.html.DeviceMotionEvent;
import js.html.InputElement;
import js.lib.Float32Array;
import js.lib.Int32Array;
import js.lib.Promise;
import js.lib.WebAssembly;
import muun.la.Mat2;
import muun.la.Vec2;
import pot.core.App;
import pot.graphics.gl.Graphics;
import pot.graphics.gl.Object;
import pot.graphics.gl.Shader;
import pot.util.XorShift;

private enum abstract ParticleField(Int) to Int {
	final AERATION;
	final POS_X;
	final POS_Y;
	final VEL_X;
	final VEL_Y;
	final GVEL_00;
	final GVEL_01;
	final GVEL_10;
	final GVEL_11;
	final DENSITY;
	final SIZE;
}

private enum abstract CellField(Int) to Int {
	final MASS;
	final AERATION;
	final VEL_X;
	final VEL_Y;
	final DVEL_X;
	final DVEL_Y;
	final SIZE;
}

class Main extends App {
	var g:Graphics;

	static inline final MAX_PARTICLES:Int = 262144;

	var numP:Int = 0;

	static inline final MAX_CELLS:Int = 262144;

	var pdata:Float32Array = new Float32Array(MAX_PARTICLES * ParticleField.SIZE);
	var cdata:Float32Array = new Float32Array(MAX_CELLS * CellField.SIZE);

	var scale:Float = 8.0;

	static inline final PDELTA:Float = 0.5;
	static inline final DENSITY:Float = 1 / (PDELTA * PDELTA);
	static inline final INV_DENSITY:Float = 1 / DENSITY;
	static inline final GRAVITY:Float = 0.0075;
	static inline final SUBSTEP:Int = 2;

	static inline final AERATION_THRESHOLD:Float = 0.7;
	static inline final AERATION_COEFF:Float = 20.0;
	static inline final AERATION_BLUR:Float = 0.01;
	static inline final AERATION_DAMP:Float = 0.992;

	final rand:XorShift = new XorShift();
	var gridW:Int = 0;
	var gridH:Int = 0;
	var numC:Int = 0;

	var accX:Float = 0;
	var accY:Float = -9.80665;

	var mesh:Object;

	var shader:Shader;

	var wasm:WasmLogic;

	var useWasm:Bool = false;
	var deviceMotionEnabled:Bool = false;

	override function setup():Void {
		g = new Graphics(canvas);
		g.init2D();

		mesh = g.createObject();
		shader = g.createShader(WaterShader.vertexSource, WaterShader.fragmentSource);

		final request:() -> Promise<String> = untyped DeviceMotionEvent.requestPermission;
		var deviceMotionAdded:Bool = false;
		final addDeviceMotionEvent = () -> {
			if (deviceMotionAdded)
				return;
			deviceMotionAdded = true;
			// everything weird thanks to Apple, see https://blog.oimo.io/2023/11/28/devicemotion/
			final sign = ~/iPhone|Macintosh/.match(Browser.navigator.userAgent) ? -1.0 : 1.0;
			Browser.window.addEventListener("devicemotion", (e:DeviceMotionEvent) -> {
				if (!deviceMotionEnabled) {
					accX = 0;
					accY = -9.80665;
					return;
				}
				if (e.accelerationIncludingGravity == null || e.acceleration == null)
					return;
				final rot = Math.isFinite(Browser.window.orientation) ? Mat2.rot(Browser.window.orientation * Math.PI / 180) : Mat2.id;
				final accG = rot * Vec2.of(e.accelerationIncludingGravity.x, e.accelerationIncludingGravity.y);
				final acc = rot * Vec2.of(e.acceleration.x, e.acceleration.y);
				if (acc.length + accG.length == 0.0)
					return;
				final accOnlyG = (accG - acc) / 9.80665;
				if (accOnlyG.length > 0.5) {
					accOnlyG <<= accOnlyG.normalized;
				}
				accOnlyG <<= accOnlyG * 9.80665;

				final accSum = (accOnlyG + 20 * acc) * sign;
				this.accX = -accSum.x;
				this.accY = -accSum.y;
			});
		};

		pot.frameRate(Fixed(60));

		final low:InputElement = cast Browser.document.getElementById("low");
		final medium:InputElement = cast Browser.document.getElementById("medium");
		final high:InputElement = cast Browser.document.getElementById("high");
		final sup:InputElement = cast Browser.document.getElementById("super");
		final changeRes = function(scale:Float) {
			var coeff = 1 / (1 + (Browser.window.devicePixelRatio - 1) * 0.5);
			final maxRes = 1000 * 1000;
			final res = pot.width * pot.height;
			coeff *= Math.sqrt(Math.max(1, res / maxRes));
			this.scale = scale * coeff;
			initSimulation();
		}

		final enableWasm:InputElement = cast Browser.document.getElementById("wasm");
		final enableAcc:InputElement = cast Browser.document.getElementById("acc");

		useWasm = enableWasm.checked;

		enableWasm.oninput = function() {
			useWasm = enableWasm.checked;
		}

		enableAcc.oninput = function() {
			deviceMotionEnabled = enableAcc.checked;
			if (deviceMotionEnabled && !deviceMotionAdded) {
				// try to add event
				if (request == null) {
					addDeviceMotionEvent();
				} else {
					request().then(state -> {
						if (state == "granted") {
							addDeviceMotionEvent();
						} else {
							deviceMotionEnabled = false;
							enableAcc.checked = false;
						}
					});
				}
			}
		}

		Browser.window.fetch("main.wasm").then(res -> WebAssembly.instantiateStreaming(res, {}).then((res) -> {
			final exports = res.instance.exports;

			wasm = cast {
			};

			// protect functions from closure compiler
			Syntax.code("{0}.particles = {1}[\"particles\"];", wasm, exports);
			Syntax.code("{0}.cells = {1}[\"cells\"];", wasm, exports);
			Syntax.code("{0}.setGrid = {1}[\"setGrid\"];", wasm, exports);
			Syntax.code("{0}.p2g = {1}[\"p2g\"];", wasm, exports);
			Syntax.code("{0}.updateGrid = {1}[\"updateGrid\"];", wasm, exports);
			Syntax.code("{0}.g2p = {1}[\"g2p\"];", wasm, exports);
			Syntax.code("{0}.memory = {1}[\"memory\"];", wasm, exports);
			Syntax.code("{0}.numP = {1}[\"numP\"];", wasm, exports);

			pdata = new Float32Array(wasm.memory.buffer, wasm.particles());
			cdata = new Float32Array(wasm.memory.buffer, wasm.cells());

			low.onclick = changeRes.bind(16);
			medium.onclick = changeRes.bind(12);
			high.onclick = changeRes.bind(8);
			sup.onclick = changeRes.bind(4);
			high.click();
			pot.start();
		}));
	}

	function initSimulation():Void {
		mesh.mode = Points;
		mesh.writer.clear();
		mesh.material.shader = shader;
		numP = 0;
		// spawnBox(pot.width * 0.5, 200, 200, 200);
		// spawnBox(pot.width * 0.5, 110, 200, 200);
		// spawnBox(pot.width * 0.5, pot.height - 160, pot.width - 50, 300);
		final isqrt2 = Math.sqrt(0.5);

		spawnBox(pot.width * 0.5 / scale, pot.height * 0.5 / scale, pot.width / scale * isqrt2, pot.height / scale * isqrt2);

		// addParticle(pot.width * 0.5 / SCALE, pot.height * 0.5 / SCALE);

		// spawnBox(pot.width * 0.5 / SCALE, pot.height * 0.5 / SCALE, 200 / SCALE, 200 / SCALE);
		// for (i in 0...5) {
		// 	for (j in 0...3) {
		// 		spawnBox(pot.width * 0.5 + (j - 1) * 180, 80 + i * 120, 150, 100);
		// 	}
		// }
		mesh.writer.upload();

		// sync numP
		new Int32Array(wasm.memory.buffer, wasm.numP.value)[0] = numP;

		trace("particles: " + numP);
	}

	function spawnBox(cx:Float, cy:Float, w:Float, h:Float):Void {
		final y1 = cy - h * 0.5;
		final y2 = cy + h * 0.5;
		final x1 = cx - w * 0.5;
		final x2 = cx + w * 0.5;

		var y = y1;
		while (y < y2) {
			var x = x1;
			while (x < x2) {
				addParticle(x, y);
				x += PDELTA;
			}
			y += PDELTA;
		}
	}

	function addParticle(x:Float, y:Float):Void {
		if (numP == MAX_PARTICLES)
			return;
		var p = numP * ParticleField.SIZE;
		pdata[p++] = 0;
		pdata[p++] = x;
		pdata[p++] = y;
		pdata[p++] = 0;
		pdata[p++] = 0;
		pdata[p++] = 0;
		pdata[p++] = 0;
		pdata[p++] = 0;
		pdata[p++] = 0;
		pdata[p++] = 0;
		numP++;
		mesh.writer.vertex(0, 0, 0);
	}

	function updateMesh():Void {
		final colorData = mesh.writer.colorWriter.data;
		var p = 0;
		var colIdx = 0;
		final pixelScale = canvas.width / pot.width;
		for (i in 0...numP) {
			final px = pdata[p + ParticleField.POS_X];
			final py = pdata[p + ParticleField.POS_Y];
			final vx = pdata[p + ParticleField.VEL_X];
			final vy = pdata[p + ParticleField.VEL_Y];
			final d = pdata[p + ParticleField.DENSITY] * INV_DENSITY;
			final pos = Vec2.of(px, py) * scale;
			final s = scale * PDELTA * 0.85 * min(d + 0.5, 1.5) * 2 * pixelScale;
			final t = clamp(pdata[p + ParticleField.AERATION], 0, 1);
			colorData[colIdx++] = pos.x;
			colorData[colIdx++] = pos.y;
			colorData[colIdx++] = s;
			colorData[colIdx++] = t;
			p += ParticleField.SIZE;
		}
		mesh.writer.colorWriter.upload(true);
	}

	override function update():Void {
		// if (input.keyboard[Space].ddown == 1)
		// 	initSimulation();

		final st = Timer.stamp();
		for (t in 0...SUBSTEP) {
			if (useWasm)
				stepWasm();
			else
				step();
		}
		updateMesh();
		final en = Timer.stamp();
		static final info = Browser.document.getElementById("info");
		info.innerHTML = "Particles: "
			+ numP
			+ "<br>Time: "
			+ Math.round((en - st) * 1000 * 1000) / 1000
			+ "ms ("
			+ (useWasm ? "WASM" : "JS")
			+ ")";
	}

	function prepareGrid():Void {
		gridW = Std.int(pot.width / scale) + 1;
		gridH = Std.int(pot.height / scale) + 1;
		numC = gridW * gridH;
		var p = 0;
		for (y in 0...gridH) {
			for (x in 0...gridW) {
				cdata[p++] = 0;
				cdata[p++] = 0;
				cdata[p++] = 0;
				cdata[p++] = 0;
				cdata[p++] = 0;
				cdata[p++] = 0;
			}
		}
	}

	extern inline function clamp(x:Float, min:Float, max:Float):Float {
		return x < min ? min : x > max ? max : x;
	}

	extern inline function clampi(x:Int, min:Int, max:Int):Int {
		return x < min ? min : x > max ? max : x;
	}

	extern inline function mirror(c1:Int, c2:Int):Void {
		c1 *= CellField.SIZE;
		c2 *= CellField.SIZE;
		final m = cdata[c1 + CellField.MASS] + cdata[c2 + CellField.MASS];
		final mx = cdata[c1 + CellField.VEL_X] + cdata[c2 + CellField.VEL_X];
		final my = cdata[c1 + CellField.VEL_Y] + cdata[c2 + CellField.VEL_Y];
		cdata[c1 + CellField.MASS] = m;
		cdata[c2 + CellField.MASS] = m;
		cdata[c1 + CellField.VEL_X] = mx;
		cdata[c2 + CellField.VEL_X] = mx;
		cdata[c1 + CellField.VEL_Y] = my;
		cdata[c2 + CellField.VEL_Y] = my;
	}

	extern inline function mirror2(c1:Int, c2:Int, flipx:Bool, flipy:Bool):Void {
		c1 *= CellField.SIZE;
		c2 *= CellField.SIZE;
		if (flipx) {
			final subx = cdata[c1 + CellField.DVEL_X] - cdata[c2 + CellField.DVEL_X];
			cdata[c1 + CellField.DVEL_X] = subx;
			cdata[c2 + CellField.DVEL_X] = -subx;
		} else {
			final sumx = cdata[c1 + CellField.DVEL_X] + cdata[c2 + CellField.DVEL_X];
			cdata[c1 + CellField.DVEL_X] = sumx;
			cdata[c2 + CellField.DVEL_X] = sumx;
		}
		if (flipy) {
			final suby = cdata[c1 + CellField.DVEL_Y] - cdata[c2 + CellField.DVEL_Y];
			cdata[c1 + CellField.DVEL_Y] = suby;
			cdata[c2 + CellField.DVEL_Y] = -suby;
		} else {
			final sumy = cdata[c1 + CellField.DVEL_Y] + cdata[c2 + CellField.DVEL_Y];
			cdata[c1 + CellField.DVEL_Y] = sumy;
			cdata[c2 + CellField.DVEL_Y] = sumy;
		}
	}

	function step():Void {
		prepareGrid();

		final pdata = this.pdata;
		final cdata = this.cdata;

		// mass and momentum transfer
		final deltaIdxY = gridW * CellField.SIZE;
		for (i in 0...numP) {
			final off = i * ParticleField.SIZE;
			var p = off;
			final a = pdata[p++];
			final px = pdata[p++];
			final py = pdata[p++];
			final vx = pdata[p++];
			final vy = pdata[p++];
			final gv00 = pdata[p++];
			final gv01 = pdata[p++];
			final gv10 = pdata[p++];
			final gv11 = pdata[p++];
			final gx = Std.int(px);
			final gy = Std.int(py);
			final cidx = ((gy - 1) * gridW + (gx - 1)) * CellField.SIZE;

			final dx = gx + 0.5 - px;
			final dy = gy + 0.5 - py;
			final wx0 = (dx + 0.5) * (dx + 0.5) * 0.5;
			final wx1 = 0.75 - dx * dx;
			final wx2 = (dx - 0.5) * (dx - 0.5) * 0.5;
			final wy0 = (dy + 0.5) * (dy + 0.5) * 0.5;
			final wy1 = 0.75 - dy * dy;
			final wy2 = (dy - 0.5) * (dy - 0.5) * 0.5;

			final c00 = cidx;
			final c01 = c00 + CellField.SIZE;
			final c02 = c01 + CellField.SIZE;
			final c10 = c00 + deltaIdxY;
			final c11 = c01 + deltaIdxY;
			final c12 = c02 + deltaIdxY;
			final c20 = c10 + deltaIdxY;
			final c21 = c11 + deltaIdxY;
			final c22 = c12 + deltaIdxY;

			final gv00x = gv00 * dx;
			final gv01y = gv01 * dy;
			final gv10x = gv10 * dx;
			final gv11y = gv11 * dy;

			final cvx = vx + gv00x + gv01y;
			final cvy = vy + gv10x + gv11y;

			var w;
			var p;

			w = wy0 * wx0;
			cdata[c00 + CellField.MASS] += w;
			cdata[c00 + CellField.AERATION] += w * a;
			cdata[c00 + CellField.VEL_X] += w * (cvx - gv00 - gv01);
			cdata[c00 + CellField.VEL_Y] += w * (cvy - gv10 - gv11);
			w = wy0 * wx1;
			cdata[c01 + CellField.MASS] += w;
			cdata[c01 + CellField.AERATION] += w * a;
			cdata[c01 + CellField.VEL_X] += w * (cvx - gv01);
			cdata[c01 + CellField.VEL_Y] += w * (cvy - gv11);
			w = wy0 * wx2;
			cdata[c02 + CellField.MASS] += w;
			cdata[c02 + CellField.AERATION] += w * a;
			cdata[c02 + CellField.VEL_X] += w * (cvx + gv00 - gv01);
			cdata[c02 + CellField.VEL_Y] += w * (cvy + gv10 - gv11);

			w = wy1 * wx0;
			cdata[c10 + CellField.MASS] += w;
			cdata[c10 + CellField.AERATION] += w * a;
			cdata[c10 + CellField.VEL_X] += w * (cvx - gv00);
			cdata[c10 + CellField.VEL_Y] += w * (cvy - gv10);
			w = wy1 * wx1;
			cdata[c11 + CellField.MASS] += w;
			cdata[c11 + CellField.AERATION] += w * a;
			cdata[c11 + CellField.VEL_X] += w * cvx;
			cdata[c11 + CellField.VEL_Y] += w * cvy;
			w = wy1 * wx2;
			cdata[c12 + CellField.MASS] += w;
			cdata[c12 + CellField.AERATION] += w * a;
			cdata[c12 + CellField.VEL_X] += w * (cvx + gv00);
			cdata[c12 + CellField.VEL_Y] += w * (cvy + gv10);

			w = wy2 * wx0;
			cdata[c20 + CellField.MASS] += w;
			cdata[c20 + CellField.AERATION] += w * a;
			cdata[c20 + CellField.VEL_X] += w * (cvx - gv00 + gv01);
			cdata[c20 + CellField.VEL_Y] += w * (cvy - gv10 + gv11);
			w = wy2 * wx1;
			cdata[c21 + CellField.MASS] += w;
			cdata[c21 + CellField.AERATION] += w * a;
			cdata[c21 + CellField.VEL_X] += w * (cvx + gv01);
			cdata[c21 + CellField.VEL_Y] += w * (cvy + gv11);
			w = wy2 * wx2;
			cdata[c22 + CellField.MASS] += w;
			cdata[c22 + CellField.AERATION] += w * a;
			cdata[c22 + CellField.VEL_X] += w * (cvx + gv00 + gv01);
			cdata[c22 + CellField.VEL_Y] += w * (cvy + gv10 + gv11);
		}

		// normalize aeration
		{
			var p = 0;
			for (i in 0...numC) {
				final mass = cdata[p + CellField.MASS];
				if (mass > 0) {
					cdata[p + CellField.AERATION] /= mass;
				}
				p += CellField.SIZE;
			}
		}

		// symmetric boundary condition
		for (i in 0...gridH) {
			final n = gridW - 1;
			final off = i * gridW;
			mirror(off, off + 1);
			mirror(off + n, off + n - 1);
		}
		for (j in 0...gridW) {
			final n = gridH - 1;
			mirror(j, j + gridW);
			mirror(j + n * gridW, j + (n - 1) * gridW);
		}

		// apply pressure
		for (i in 0...numP) {
			final off = i * ParticleField.SIZE;
			final a = pdata[off + ParticleField.AERATION];
			final px = pdata[off + ParticleField.POS_X];
			final py = pdata[off + ParticleField.POS_Y];
			final gx = Std.int(px);
			final gy = Std.int(py);
			final cidx = ((gy - 1) * gridW + (gx - 1)) * CellField.SIZE;

			final dx = gx + 0.5 - px;
			final dy = gy + 0.5 - py;
			final wx0 = (dx + 0.5) * (dx + 0.5) * 0.5;
			final wx1 = 0.75 - dx * dx;
			final wx2 = (dx - 0.5) * (dx - 0.5) * 0.5;
			final wy0 = (dy + 0.5) * (dy + 0.5) * 0.5;
			final wy1 = 0.75 - dy * dy;
			final wy2 = (dy - 0.5) * (dy - 0.5) * 0.5;

			final w00 = wy0 * wx0;
			final w01 = wy0 * wx1;
			final w02 = wy0 * wx2;
			final w10 = wy1 * wx0;
			final w11 = wy1 * wx1;
			final w12 = wy1 * wx2;
			final w20 = wy2 * wx0;
			final w21 = wy2 * wx1;
			final w22 = wy2 * wx2;

			final c00 = cidx;
			final c01 = c00 + CellField.SIZE;
			final c02 = c01 + CellField.SIZE;
			final c10 = c00 + deltaIdxY;
			final c11 = c01 + deltaIdxY;
			final c12 = c02 + deltaIdxY;
			final c20 = c10 + deltaIdxY;
			final c21 = c11 + deltaIdxY;
			final c22 = c12 + deltaIdxY;

			var density = 0.0;
			var aeration = 0.0;

			density += w00 * cdata[c00 + CellField.MASS];
			density += w01 * cdata[c01 + CellField.MASS];
			density += w02 * cdata[c02 + CellField.MASS];
			density += w10 * cdata[c10 + CellField.MASS];
			density += w11 * cdata[c11 + CellField.MASS];
			density += w12 * cdata[c12 + CellField.MASS];
			density += w20 * cdata[c20 + CellField.MASS];
			density += w21 * cdata[c21 + CellField.MASS];
			density += w22 * cdata[c22 + CellField.MASS];
			aeration += w00 * cdata[c00 + CellField.AERATION];
			aeration += w01 * cdata[c01 + CellField.AERATION];
			aeration += w02 * cdata[c02 + CellField.AERATION];
			aeration += w10 * cdata[c10 + CellField.AERATION];
			aeration += w11 * cdata[c11 + CellField.AERATION];
			aeration += w12 * cdata[c12 + CellField.AERATION];
			aeration += w20 * cdata[c20 + CellField.AERATION];
			aeration += w21 * cdata[c21 + CellField.AERATION];
			aeration += w22 * cdata[c22 + CellField.AERATION];

			// set density
			pdata[off + ParticleField.DENSITY] = density;

			// update aeration
			pdata[off + ParticleField.AERATION] = AERATION_DAMP * (a + (aeration - a) * AERATION_BLUR);

			var pressure = (density / DENSITY - 1) * 5.0;
			if (pressure < 0)
				pressure = 0;

			final volume = 1 / density; // mass is 1
			final coeff = volume * 4 * -pressure;
			final coeffx = coeff * dx;
			final coeffy = coeff * dy;

			final coeffx0 = coeffx - coeff;
			final coeffx1 = coeffx;
			final coeffx2 = coeffx + coeff;
			final coeffy0 = coeffy - coeff;
			final coeffy1 = coeffy;
			final coeffy2 = coeffy + coeff;

			cdata[c00 + CellField.DVEL_X] -= w00 * coeffx0;
			cdata[c00 + CellField.DVEL_Y] -= w00 * coeffy0;
			cdata[c01 + CellField.DVEL_X] -= w01 * coeffx1;
			cdata[c01 + CellField.DVEL_Y] -= w01 * coeffy0;
			cdata[c02 + CellField.DVEL_X] -= w02 * coeffx2;
			cdata[c02 + CellField.DVEL_Y] -= w02 * coeffy0;

			cdata[c10 + CellField.DVEL_X] -= w10 * coeffx0;
			cdata[c10 + CellField.DVEL_Y] -= w10 * coeffy1;
			cdata[c11 + CellField.DVEL_X] -= w11 * coeffx1;
			cdata[c11 + CellField.DVEL_Y] -= w11 * coeffy1;
			cdata[c12 + CellField.DVEL_X] -= w12 * coeffx2;
			cdata[c12 + CellField.DVEL_Y] -= w12 * coeffy1;

			cdata[c20 + CellField.DVEL_X] -= w20 * coeffx0;
			cdata[c20 + CellField.DVEL_Y] -= w20 * coeffy2;
			cdata[c21 + CellField.DVEL_X] -= w21 * coeffx1;
			cdata[c21 + CellField.DVEL_Y] -= w21 * coeffy2;
			cdata[c22 + CellField.DVEL_X] -= w22 * coeffx2;
			cdata[c22 + CellField.DVEL_Y] -= w22 * coeffy2;
		}

		// symmetric boundary condition
		for (i in 0...gridH) {
			final n = gridW - 1;
			final off = i * gridW;
			mirror2(off, off + 1, true, false);
			mirror2(off + n, off + n - 1, true, false);
		}
		for (j in 0...gridW) {
			final n = gridH - 1;
			mirror2(j, j + gridW, false, true);
			mirror2(j + n * gridW, j + (n - 1) * gridW, false, true);
		}

		final touching = input.touches.length > 0;
		final touch = touching ? input.touches[0] : null;
		final mouse = touching ? Vec2.of(touch.x, touch.y) : Vec2.of(input.mouse.x, input.mouse.y);
		mouse /= scale;
		final dmouse = touching ? Vec2.of(touch.dx, touch.dy) : Vec2.of(input.mouse.dx, input.mouse.dy);
		dmouse /= scale * SUBSTEP;
		final rad = 5;
		final stop = false;

		if (!(touching && touch.touching || input.mouse.left)) {
			mouse.x = -256;
			mouse.y = -256;
		}

		final gx = accX / 9.80665 * GRAVITY;
		final gy = -accY / 9.80665 * GRAVITY;

		// momentum to velocity
		{
			var p = 0;
			for (i in 0...gridH) {
				for (j in 0...gridW) {
					final mass = cdata[p + CellField.MASS];
					if (mass > 0) {
						final invm = 1 / mass;
						final mx = cdata[p + CellField.VEL_X] + cdata[p + CellField.DVEL_X];
						final my = cdata[p + CellField.VEL_Y] + cdata[p + CellField.DVEL_Y];
						var vx = mx * invm + gx;
						var vy = my * invm + gy;

						// mouse interaction
						final dx = mouse.x - (j + 0.5);
						final dy = mouse.y - (i + 0.5);
						final r2 = dx * dx + dy * dy;
						if (r2 < rad * rad) {
							final r = Math.sqrt(r2);
							final coeff = r < 0.5 * rad ? 1 : 2 - r / rad * 2;
							vx += coeff * (dmouse.x - vx);
							vy += coeff * (dmouse.y - vy);
						}

						if (stop) {
							vx = 0;
							vy = 0;
						}

						cdata[p + CellField.VEL_X] = vx;
						cdata[p + CellField.VEL_Y] = vy;
					} else {
						cdata[p + CellField.VEL_X] = 0;
						cdata[p + CellField.VEL_Y] = 0;
					}
					p += CellField.SIZE;
				}
			}
		}

		// boundary condition
		{
			var p = 0;
			for (i in 0...gridH) {
				for (j in 0...gridW) {
					if (j == 0)
						cdata[p + CellField.VEL_X] = -cdata[p + CellField.SIZE + CellField.VEL_X];
					if (j == gridW - 1)
						cdata[p + CellField.VEL_X] = -cdata[p - CellField.SIZE + CellField.VEL_X];
					if (i == 0)
						cdata[p + CellField.VEL_Y] = -cdata[p + CellField.SIZE * gridW + CellField.VEL_Y];
					if (i == gridH - 1)
						cdata[p + CellField.VEL_Y] = -cdata[p - CellField.SIZE * gridW + CellField.VEL_Y];
					// TODO: reflect
					if (j == 0 && cdata[p + CellField.VEL_X] < 0)
						cdata[p + CellField.VEL_X] *= -1;
					if (j == gridW - 1 && cdata[p + CellField.VEL_X] > 0)
						cdata[p + CellField.VEL_X] *= -1;
					if (i == 0 && cdata[p + CellField.VEL_Y] < 0)
						cdata[p + CellField.VEL_Y] *= -1;
					if (i == gridH - 1 && cdata[p + CellField.VEL_Y] > 0)
						cdata[p + CellField.VEL_Y] *= -1;
					p += CellField.SIZE;
				}
			}
		}

		// grid to particle
		for (i in 0...numP) {
			final off = i * ParticleField.SIZE;
			final px = pdata[off + ParticleField.POS_X];
			final py = pdata[off + ParticleField.POS_Y];
			final pvx = pdata[off + ParticleField.VEL_X];
			final pvy = pdata[off + ParticleField.VEL_Y];
			final gx = Std.int(px);
			final gy = Std.int(py);
			var cidx = ((gy - 1) * gridW + (gx - 1)) * CellField.SIZE;

			final dx = gx + 0.5 - px;
			final dy = gy + 0.5 - py;
			final wx0 = (dx + 0.5) * (dx + 0.5) * 0.5;
			final wx1 = 0.75 - dx * dx;
			final wx2 = (dx - 0.5) * (dx - 0.5) * 0.5;
			final wy0 = (dy + 0.5) * (dy + 0.5) * 0.5;
			final wy1 = 0.75 - dy * dy;
			final wy2 = (dy - 0.5) * (dy - 0.5) * 0.5;

			final c00 = cidx;
			final c01 = c00 + CellField.SIZE;
			final c02 = c01 + CellField.SIZE;
			final c10 = c00 + deltaIdxY;
			final c11 = c01 + deltaIdxY;
			final c12 = c02 + deltaIdxY;
			final c20 = c10 + deltaIdxY;
			final c21 = c11 + deltaIdxY;
			final c22 = c12 + deltaIdxY;

			var vx = 0.0;
			var vy = 0.0;
			var gv00 = 0.0;
			var gv01 = 0.0;
			var gv10 = 0.0;
			var gv11 = 0.0;

			var w;
			var wvx;
			var wvy;

			w = wy0 * wx0;
			wvx = w * cdata[c00 + CellField.VEL_X];
			wvy = w * cdata[c00 + CellField.VEL_Y];
			vx += wvx;
			vy += wvy;
			gv00 -= wvx;
			gv01 -= wvx;
			gv10 -= wvy;
			gv11 -= wvy;
			w = wy0 * wx1;
			wvx = w * cdata[c01 + CellField.VEL_X];
			wvy = w * cdata[c01 + CellField.VEL_Y];
			vx += wvx;
			vy += wvy;
			gv01 -= wvx;
			gv11 -= wvy;
			w = wy0 * wx2;
			wvx = w * cdata[c02 + CellField.VEL_X];
			wvy = w * cdata[c02 + CellField.VEL_Y];
			vx += wvx;
			vy += wvy;
			gv00 += wvx;
			gv01 -= wvx;
			gv10 += wvy;
			gv11 -= wvy;

			w = wy1 * wx0;
			wvx = w * cdata[c10 + CellField.VEL_X];
			wvy = w * cdata[c10 + CellField.VEL_Y];
			vx += wvx;
			vy += wvy;
			gv00 -= wvx;
			gv10 -= wvy;
			w = wy1 * wx1;
			wvx = w * cdata[c11 + CellField.VEL_X];
			wvy = w * cdata[c11 + CellField.VEL_Y];
			vx += wvx;
			vy += wvy;
			w = wy1 * wx2;
			wvx = w * cdata[c12 + CellField.VEL_X];
			wvy = w * cdata[c12 + CellField.VEL_Y];
			vx += wvx;
			vy += wvy;
			gv00 += wvx;
			gv10 += wvy;

			w = wy2 * wx0;
			wvx = w * cdata[c20 + CellField.VEL_X];
			wvy = w * cdata[c20 + CellField.VEL_Y];
			vx += wvx;
			vy += wvy;
			gv00 -= wvx;
			gv01 += wvx;
			gv10 -= wvy;
			gv11 += wvy;
			w = wy2 * wx1;
			wvx = w * cdata[c21 + CellField.VEL_X];
			wvy = w * cdata[c21 + CellField.VEL_Y];
			vx += wvx;
			vy += wvy;
			gv01 += wvx;
			gv11 += wvy;
			w = wy2 * wx2;
			wvx = w * cdata[c22 + CellField.VEL_X];
			wvy = w * cdata[c22 + CellField.VEL_Y];
			vx += wvx;
			vy += wvy;
			gv00 += wvx;
			gv01 += wvx;
			gv10 += wvy;
			gv11 += wvy;

			gv00 = 4 * (gv00 + vx * dx);
			gv01 = 4 * (gv01 + vx * dy);
			gv10 = 4 * (gv10 + vy * dx);
			gv11 = 4 * (gv11 + vy * dy);

			final ONE = 1 + 1e-3;
			final npx = clamp(px + vx, ONE, gridW - ONE);
			final npy = clamp(py + vy, ONE, gridH - ONE);
			vx = npx - px;
			vy = npy - py;

			final ax = vx - pvx;
			final ay = vy - pvy;
			final alen = Math.sqrt(ax * ax + ay * ay);
			final densityRatio = pdata[off + ParticleField.DENSITY] / DENSITY;
			if (densityRatio < AERATION_THRESHOLD) {
				final a = pdata[off + ParticleField.AERATION] + alen * (1 - densityRatio / AERATION_THRESHOLD) * AERATION_COEFF;
				pdata[off + ParticleField.AERATION] = min(1, a);
			}

			pdata[off + ParticleField.POS_X] = npx + rand.nextFloat(-1e-4, 1e-4);
			pdata[off + ParticleField.POS_Y] = npy + rand.nextFloat(-1e-4, 1e-4);
			pdata[off + ParticleField.VEL_X] = vx;
			pdata[off + ParticleField.VEL_Y] = vy;
			pdata[off + ParticleField.GVEL_00] = gv00;
			pdata[off + ParticleField.GVEL_01] = gv01;
			pdata[off + ParticleField.GVEL_10] = gv10;
			pdata[off + ParticleField.GVEL_11] = gv11;
		}
	}

	function stepWasm():Void {
		gridW = Std.int(pot.width / scale) + 1;
		gridH = Std.int(pot.height / scale) + 1;
		numC = gridW * gridH;
		wasm.setGrid(gridW, gridH);

		final touching = input.touches.length > 0;
		final touch = touching ? input.touches[0] : null;
		final mouse = touching ? Vec2.of(touch.x, touch.y) : Vec2.of(input.mouse.x, input.mouse.y);
		mouse /= scale;
		final dmouse = touching ? Vec2.of(touch.dx, touch.dy) : Vec2.of(input.mouse.dx, input.mouse.dy);
		dmouse /= scale * SUBSTEP;
		final rad = 5;
		final stop = false;

		if (!(touching && touch.touching || input.mouse.left)) {
			mouse.x = -256;
			mouse.y = -256;
		}

		final gx = accX / 9.80665 * GRAVITY;
		final gy = -accY / 9.80665 * GRAVITY;

		wasm.p2g();
		wasm.updateGrid(gx, gy, mouse.x, mouse.y, dmouse.x, dmouse.y, rad);
		wasm.g2p();

		// add randomness to avoid particle clustering
		for (i in 0...numP) {
			pdata[i * ParticleField.SIZE + ParticleField.POS_X] += rand.nextFloat(-1e-4, 1e-4);
			pdata[i * ParticleField.SIZE + ParticleField.POS_Y] += rand.nextFloat(-1e-4, 1e-4);
		}
	}

	override function draw():Void {
		g.screen(pot.width, pot.height);
		g.inScene(renderScene);
	}

	function renderScene():Void {
		g.clear(0.1, 0.1, 0.1);

		final drawCellColor = false;
		final drawGrid = false;
		final drawVel = false;
		final drawParticles = true;

		if (drawCellColor) {
			g.shaping(Triangles, () -> {
				// var p = 0;
				// for (i in 0...gridH) {
				// 	for (j in 0...gridW) {
				// 		final x = (j + 0.5) * scale;
				// 		final y = (i + 0.5) * scale;
				// 		final d = 0.5 * scale;
				// 		var f = cdata[p + CellField.MASS] / DENSITY;
				// 		g.color(f, 0, 1 - f);
				// 		g.vertex(x - d, y - d);
				// 		g.vertex(x - d, y + d);
				// 		g.vertex(x + d, y + d);
				// 		g.vertex(x - d, y - d);
				// 		g.vertex(x + d, y + d);
				// 		g.vertex(x + d, y - d);
				// 		p += CellField.SIZE;
				// 	}
				// }

				final wasmCs = new Float32Array(wasm.memory.buffer, wasm.cells());
				var p = 0;
				for (i in 0...gridH) {
					for (j in 0...gridW) {
						final x = (j + 0.5) * scale;
						final y = (i + 0.5) * scale;
						final d = 0.5 * scale;
						var f = wasmCs[p + CellField.MASS] * INV_DENSITY;
						g.color(f, 0, 1 - f);
						g.vertex(x - d, y - d);
						g.vertex(x - d, y + d);
						g.vertex(x + d, y + d);
						g.vertex(x - d, y - d);
						g.vertex(x + d, y + d);
						g.vertex(x + d, y - d);
						p += CellField.SIZE;
					}
				}
			});
		}
		g.shaping(Lines, () -> {
			if (drawGrid) {
				g.color(1, 1, 1, 0.2);
				{
					var x = scale;
					while (x < pot.width) {
						g.vertex(x, 0);
						g.vertex(x, pot.height);
						x += scale;
					}
				}
				{
					var y = scale;
					while (y < pot.height) {
						g.vertex(0, y);
						g.vertex(pot.width, y);
						y += scale;
					}
				}
			}
			if (drawVel) {
				g.color(1, 1, 1);
				// var cidx = 0;
				// for (i in 0...gridH) {
				// 	for (j in 0...gridW) {
				// 		final x = (j + 0.5) * scale;
				// 		final y = (i + 0.5) * scale;
				// 		final vx = cdata[cidx + CellField.VEL_X] * 2 * scale;
				// 		final vy = cdata[cidx + CellField.VEL_Y] * 2 * scale;
				// 		g.vertex(x, y);
				// 		g.vertex(x + vx, y + vy);
				// 		cidx += CellField.SIZE;
				// 	}
				// }

				final wasmCs = new Float32Array(wasm.memory.buffer, wasm.cells());
				var cidx = 0;
				for (i in 0...gridH) {
					for (j in 0...gridW) {
						final x = (j + 0.5) * scale;
						final y = (i + 0.5) * scale;
						final vx = wasmCs[cidx + CellField.VEL_X] * 2 * scale;
						final vy = wasmCs[cidx + CellField.VEL_Y] * 2 * scale;
						g.vertex(x, y);
						g.vertex(x + vx, y + vy);
						cidx += CellField.SIZE;
					}
				}
			}
		});

		if (drawParticles) {
			g.enableDepthTest();
			g.drawObject(mesh);
			g.disableDepthTest();
		}
	}

	static function main() {
		new Main(cast Browser.document.getElementById("canvas"));
	}
}
