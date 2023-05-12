import pot.graphics.gl.UniformMap;
import pot.graphics.gl.Object;
import pot.graphics.gl.FovMode;
import pot.graphics.gl.Shader;
import pot.graphics.gl.Graphics;
import pot.graphics.gl.RenderTexture;
import js.html.InputElement;
import muun.la.Mat3;
import muun.la.Vec3;
import js.Browser;
import pot.core.App;
import Shaders;

class Main extends App {
	var g:Graphics;

	static inline final SHIFT_3D:Int = 6;
	static inline final RES_3D:Int = 64;
	static inline final UNITS:Int = 8; // UNITS^2 = RES_3D
	static inline final SHIFT_2D:Int = 9;
	static inline final RES_2D:Int = 512; // RES_2D^2 = RES_3D^3
	static inline final U_VEL_VOF:String = "uVelVof";
	static inline final U_TMP:String = "uTmp";
	static inline final U_DIV_PRS:String = "uDivPrs";
	static inline final U_TIME:String = "uTime";
	static inline final U_CENTER:String = "uCenter";
	static inline final U_PCENTER:String = "uPrevCenter";
	static inline final U_RADIUS:String = "uRadius";
	static inline final U_POWER:String = "uPower";
	static inline final U_VORTICITY:String = "uVorticity";
	static inline final U_VENTILATION:String = "uVentilation";

	var initVelVofShader:Shader;
	var advectPredictShader:Shader;
	var advectCorrectShader:Shader;
	var vorticityConfinementShader:Shader;
	var computeDivShader:Shader;
	var solvePoissonShader:Shader;
	var applyPressureShader:Shader;
	var debugShader:Shader;
	var renderShader:Shader;

	var map:UniformMap;

	var velVof:RenderTexture;
	var tmp:RenderTexture;
	var divPrs:RenderTexture;

	override function setup():Void {
		pot.frameRate(Fixed(60));
		input.scalingMode = Screen;
		g = new Graphics(canvas);

		map = g.defaultUniformMap;
		final resInfo = BaseShader.uniforms.resInfo;
		map.set(resInfo.res2.name, Int(RES_2D));
		map.set(resInfo.res3.name, Int(RES_3D));
		map.set(resInfo.invRes2.name, Float(1 / RES_2D));
		map.set(resInfo.invRes3.name, Float(1 / RES_3D));
		map.set(resInfo.shift2.name, IVec2(0, SHIFT_2D));
		map.set(resInfo.shift3.name, IVec3(0, SHIFT_3D, 2 * SHIFT_3D));
		map.set(resInfo.mask2.name, Int(RES_2D - 1));
		map.set(resInfo.mask3.name, Int(RES_3D - 1));

		g.perspective(FovMin);
		g.init3D();
		g.blend(None);
		initShaders();
		initTextures();
		pot.start();
	}

	function initTextures():Void {
		velVof = new RenderTexture(g, RES_2D, RES_2D, Float32);
		tmp = new RenderTexture(g, RES_2D, RES_2D, Float32);
		divPrs = new RenderTexture(g, RES_2D, RES_2D, Float32);
		renderTo(velVof, initVelVofShader);
	}

	function initShaders():Void {
		initVelVofShader = g.createShader(InitVofShader.vertexSource, InitVofShader.fragmentSource);
		advectPredictShader = g.createShader(AdvectPredictShader.vertexSource, AdvectPredictShader.fragmentSource);
		advectCorrectShader = g.createShader(AdvectCorrectShader.vertexSource, AdvectCorrectShader.fragmentSource);
		vorticityConfinementShader = g.createShader(VorticityConfinementShader.vertexSource, VorticityConfinementShader.fragmentSource);
		computeDivShader = g.createShader(ComputeDivShader.vertexSource, ComputeDivShader.fragmentSource);
		solvePoissonShader = g.createShader(SolvePoissonShader.vertexSource, SolvePoissonShader.fragmentSource);
		applyPressureShader = g.createShader(ApplyPressureShader.vertexSource, ApplyPressureShader.fragmentSource);
		renderShader = g.createShader(RenderShader.vertexSource, RenderShader.fragmentSource);
		debugShader = g.createShader(DebugShader.vertexSource, DebugShader.fragmentSource);
	}

	override function resized():Void {
		g.screen(pot.width, pot.height);
	}

	final sliderRadius:InputElement = cast Browser.document.getElementById("radius");
	final sliderPower:InputElement = cast Browser.document.getElementById("power");
	final sliderVorticity:InputElement = cast Browser.document.getElementById("vorticity");
	final sliderVentilation:InputElement = cast Browser.document.getElementById("ventilation");

	var vrx:Float = 0;
	var vry:Float = 0;
	var rx:Float = 0;
	var ry:Float = 0;
	var grabbing:Bool = false;
	var grabbingDist:Float = 0;
	final ballPos:Vec3 = Vec3.of(0.5, 0.5, 0.5);
	final pballPos:Vec3 = Vec3.of(0.5, 0.5, 0.5);
	var ballRadius:Float = 0.08;
	final camPos:Vec3 = Vec3.zero;
	final camTarget:Vec3 = Vec3.zero;
	final halfExtent = 1.0;

	function control():Void {
		pballPos <<= ballPos;

		var pressed = false;
		var pressing = false;
		final mouse = input.mouse;
		var screenX = 0.0;
		var screenY = 0.0;
		var dx = 0.0;
		var dy = 0.0;

		if (mouse.left) {
			dx = mouse.dx / pot.width;
			dy = mouse.dy / pot.height;
			screenX = mouse.x;
			screenY = mouse.y;
			pressed = mouse.dleft == 1;
			pressing = true;
		}

		if (input.touches.length > 0) {
			final touch = input.touches[0];
			dx = touch.dx / pot.width;
			dy = touch.dy / pot.height;
			screenX = touch.x;
			screenY = touch.y;
			pressed = touch.dtouching == 1;
			pressing = touch.touching;
		}
		screenX = screenX / pot.width * 2 - 1;
		screenY = 1 - screenY / pot.height * 2;
		if (pressing && !grabbing) {
			vrx -= dx;
			vry -= dy;
		}
		rx += vrx;
		ry += vry;
		vrx *= 0.9;
		vry *= 0.9;
		final p = Math.PI;
		rx = rx % (2 * p);
		final softLim = 0.45 * p;
		final hardLim = 0.49 * p;
		if (ry > softLim) {
			ry += (softLim - ry) * 0.5;
		}
		if (ry < -softLim) {
			ry += (-softLim - ry) * 0.5;
		}
		ry = ry > hardLim ? hardLim : ry < -hardLim ? -hardLim : ry;

		ballRadius = 0.08 * sliderRadius.valueAsNumber;

		updateCamera();

		g.screen(pot.width, pot.height);
		g.camera(camPos, camTarget, Vec3.ey);
		final touchPosWorld = g.screenToWorld(Vec3.of(screenX, screenY, 0));
		final ballPosWorld = (ballPos * 2 - 1) * halfExtent;
		final ballRadiusWorld = ballRadius * 2 * halfExtent;

		if (pressed) {
			final p = ballPosWorld - camPos;
			final d = (touchPosWorld - camPos).normalized;
			final B = -p.dot(d);
			final C = p.dot(p) - ballRadiusWorld * ballRadiusWorld;
			final D = B * B - C;
			grabbing = false;
			if (D > 0) {
				final t = -B - Math.sqrt(D);
				if (t > 0) {
					grabbing = true;
					grabbingDist = p.length;
				}
			}
		}
		if (pressing && grabbing) {
			final newBallPosWorld = camPos + (touchPosWorld - camPos).normalized * grabbingDist;
			ballPos <<= (newBallPosWorld / halfExtent + 1) * 0.5;
		}
		ballPos <<= ballPos.max(Vec3.zero + ballRadius * 1.2).min(Vec3.one - ballRadius * 1.2);
		if (!pressing) {
			grabbing = false;
		}

		g.resetCamera();
	}

	override function update():Void {
		if (frameCount < 30)
			return;

		control();

		renderTo(divPrs, computeDivShader);
		for (i in 0...4) {
			map.set(SolvePoissonShader.uniforms.parity.name, Int(i & 1));
			renderTo(divPrs, solvePoissonShader);
		}
		renderTo(velVof, applyPressureShader);

		// --- MacCormack

		// prediction
		map.set(AdvectPredictShader.uniforms.forward.name, Bool(true));
		renderTo(tmp, advectPredictShader);
		map.set(AdvectPredictShader.uniforms.forward.name, Bool(false));
		renderTo(tmp, advectPredictShader);
		// correction
		renderTo(velVof, advectCorrectShader);

		renderTo(velVof, vorticityConfinementShader);
	}

	function renderTo(tex:RenderTexture, s:Shader):Void {
		shader(s);
		tex.render();
	}

	function shader(s:Shader):Void {
		final uniforms = BaseShader.uniforms;
		map.set(uniforms.texVelVof.name, Sampler(velVof.data[0]));
		map.set(uniforms.texAdvectTmp.name, Sampler(tmp.data[0]));
		map.set(uniforms.texDivPrsWgt.name, Sampler(divPrs.data[0]));
		map.set(uniforms.time.name, Float(frameCount / 60));
		map.set(uniforms.radius.name, Float(ballRadius));
		map.set(uniforms.pcenter.name, Vec3(pballPos.x, pballPos.y, pballPos.z));
		map.set(uniforms.center.name, Vec3(ballPos.x, ballPos.y, ballPos.z));
		map.set(uniforms.power.name, Float(sliderPower.valueAsNumber));
		map.set(uniforms.vorticity.name, Float(0.06 * sliderVorticity.valueAsNumber));
		map.set(uniforms.ventilation.name, Float(sliderVentilation.valueAsNumber));
		g.shader(s);
	}

	function debugView():Void {
		shader(debugShader);
		g.screen(1, 1);
		g.inScene(() -> {
			g.clear(0, 0, 0);
			g.rect(0, 0, 1, 1);
		});
	}

	function updateCamera():Void {
		camPos.set(0, 0, 3);
		final rot = Mat3.rot(rx, Vec3.ey) * Mat3.rot(ry, Vec3.ex);
		camPos <<= rot * camPos;
		camTarget <<= rot * Vec3.of(0, -0.2, 0);
		camPos += camTarget;
	}

	function render():Void {
		g.camera(camPos, camTarget, Vec3.ey);
		map.set(RenderShader.uniforms.camPos.name, Vec3(camPos.x, camPos.y, camPos.z));
		map.set(RenderShader.uniforms.halfExtent.name, Float(halfExtent));
		shader(renderShader);
		g.screen(pot.width, pot.height);
		g.inScene(() -> {
			g.clear(0, 0.05, 0.1);
			g.blend(Normal);
			g.box(halfExtent * 2, halfExtent * 2, halfExtent * 2);
			g.blend(None);
		});
		g.resetCamera();
	}

	override function draw():Void {
		// debugView();
		render();
	}

	static function main() {
		new Main(cast Browser.document.getElementById("canvas"), false, false);
	}
}
