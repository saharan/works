package;

import ShaderUtil;
import haxe.Timer;
import hgsl.Source;
import MeshManager;
import ShaderPhys;
import js.Browser;
import js.html.InputElement;
import js.html.webgl.GL2;
import js.lib.Float32Array;
import js.lib.Int32Array;
import muun.la.Mat3;
import muun.la.Vec2;
import muun.la.Vec3;
import pot.core.App;
import pot.graphics.gl.FovMode;
import pot.graphics.gl.Graphics;
import pot.graphics.gl.Object;
import pot.graphics.gl.RenderTexture;
import pot.graphics.gl.Shader;
import pot.graphics.gl.TransformFeedbackOutput;
import pot.graphics.gl.UniformMap;
import pot.graphics.gl.VertexAttribute;
import pot.graphics.gl.VertexBuffer;
import pot.graphics.gl.low.FloatBuffer;
import pot.graphics.gl.low.IntBuffer;

using Lambda;

typedef ParticleBuffer = {
	buffer:FloatBuffer,
	vertexBuffers:Array<VertexBuffer>,
	totalSize:Int,
	pos:VertexBuffer,
	vel:VertexBuffer,
	mass:VertexBuffer,
	gvel:Array<VertexBuffer>,
	jacobian:VertexBuffer,
	deform:Array<VertexBuffer>,
	weights:Array<VertexBuffer>,
	rand:VertexBuffer
}

typedef SimSetting = {
	final PARTICLES_W:Int; // in world (npot allowed)
	final PARTICLES_H:Int;
	final PARTICLES_D:Int;
	final PARTICLE_TEX_W:Int; // in texture (npot disallowed)
	final PARTICLE_TEX_H:Int;

	final PARTICLE_SIZE:Float;
	final PARTICLE_DENSITY:Float;
	final PARTICLE_CONNECTION_THRESHOLD:Float;
	final CELL_TEX_W:Int;
	final CELL_TEX_H:Int;
	final CELL_TEX_3D_W:Int;
	final CELL_TEX_3D_H:Int;
	final CELL_TEX_3D_D:Int;
}

class Main extends App {
	var g:Graphics;

	static function log2(x:Int):Int {
		var res = 0;
		while (x > 1) {
			x >>= 1;
			res++;
		}
		return res;
	}

	static final lowSetting:SimSetting = {
		PARTICLES_W: 16,
		PARTICLES_H: 16,
		PARTICLES_D: 16,
		PARTICLE_TEX_W: 64,
		PARTICLE_TEX_H: 64,
		PARTICLE_SIZE: 0.5,
		PARTICLE_DENSITY: 1.0,
		PARTICLE_CONNECTION_THRESHOLD: 1.5,
		CELL_TEX_W: 128,
		CELL_TEX_H: 256,
		CELL_TEX_3D_W: 32,
		CELL_TEX_3D_H: 32,
		CELL_TEX_3D_D: 32
	}
	static final medSetting:SimSetting = {
		PARTICLES_W: 18,
		PARTICLES_H: 18,
		PARTICLES_D: 18,
		PARTICLE_TEX_W: 256,
		PARTICLE_TEX_H: 256,
		PARTICLE_SIZE: 0.5,
		PARTICLE_DENSITY: 1.0,
		PARTICLE_CONNECTION_THRESHOLD: 1.5,
		CELL_TEX_W: 128,
		CELL_TEX_H: 256,
		CELL_TEX_3D_W: 32,
		CELL_TEX_3D_H: 32,
		CELL_TEX_3D_D: 32
	}
	static final highSetting:SimSetting = {
		PARTICLES_W: 24,
		PARTICLES_H: 24,
		PARTICLES_D: 24,
		PARTICLE_TEX_W: 128,
		PARTICLE_TEX_H: 256,
		PARTICLE_SIZE: 0.5,
		PARTICLE_DENSITY: 1.0,
		PARTICLE_CONNECTION_THRESHOLD: 1.5,
		CELL_TEX_W: 512,
		CELL_TEX_H: 512,
		CELL_TEX_3D_W: 64,
		CELL_TEX_3D_H: 64,
		CELL_TEX_3D_D: 64
	}
	static final superSetting:SimSetting = {
		PARTICLES_W: 32,
		PARTICLES_H: 32,
		PARTICLES_D: 32,
		PARTICLE_TEX_W: 128,
		PARTICLE_TEX_H: 256,
		PARTICLE_SIZE: 0.5,
		PARTICLE_DENSITY: 1.0,
		PARTICLE_CONNECTION_THRESHOLD: 1.5,
		CELL_TEX_W: 512,
		CELL_TEX_H: 512,
		CELL_TEX_3D_W: 64,
		CELL_TEX_3D_H: 64,
		CELL_TEX_3D_D: 64
	}

	var currentSetting:SimSetting = null;
	var numParticles:Int = 0;

	var ctex:RenderTexture;
	var mtex:RenderTexture;

	final feedbackVaryings:Array<String> = ["pos", "vel", "mass", "gvel0", "gvel1", "gvel2", "deform0", "deform1", "deform2", "jacobian", "weightsX", "weightsY", "weightsZ", "rand"];

	var drawParticleShader:Shader;
	var drawVelFieldShader:Shader;
	var moveParticleShader:Shader;
	var preScatterMomentumShader:Shader;
	var scatterMomentumShader:Shader;
	var computeVelocityShader:Shader;
	var scatterMeshDataShader:Shader;
	var drawMeshShader:Shader;

	var renderRGBShader:Shader;
	var renderAlphaShader:Shader;

	var um:UniformMap;

	var particleBoxes:Object;
	var particlePoints:Object;
	var particlePointsMesh:Object;
	var particleMesh:Object;

	var velField:Object;

	var drawAsBox:Bool = false;
	var drawVelField:Bool = false;

	var pbufSrc:ParticleBuffer;
	var pbufDst:ParticleBuffer;
	var pbufSrcAttributes:Array<VertexAttribute>;

	// var mpmCpu:MPMCpu;
	var particleData:Float32Array;

	var meshVertexBuffer:IntBuffer;
	var meshIndexBuffer:IntBuffer;

	var mesh:MeshManager;

	var meshIndexData:Int32Array = null;
	var meshVertexData:Int32Array = null;

	var meshQuadCount:Int = 0;
	var meshVertexDataIndex:Int = 0;

	final rayPos:Vec3 = Vec3.zero;
	final rayDir:Vec3 = Vec3.zero;
	final prayDir:Vec3 = Vec3.zero;
	var dragging:Bool = false;

	override function setup():Void {
		pot.frameRate(Fixed(60));
		// pot.frameRate(Auto);

		g = new Graphics(canvas);

		g.perspective(FovMin);
		g.init3D();
		g.disableDepthTest();

		um = g.defaultUniformMap;

		initShaders();

		inline function createParticleBuffer():ParticleBuffer {
			final res = g.createFloatVertexBufferInterleaved([3, 3, 1, 3, 3, 3, 3, 3, 3, 1, 3, 3, 3, 3]);
			final bufs = res.vertexBuffers;
			var i = 0;
			return {
				buffer: res.buffer,
				vertexBuffers: res.vertexBuffers,
				totalSize: res.totalSize,
				pos: bufs[i++],
				vel: bufs[i++],
				mass: bufs[i++],
				gvel: [bufs[i++], bufs[i++], bufs[i++]],
				deform: [bufs[i++], bufs[i++], bufs[i++]],
				jacobian: bufs[i++],
				weights: [bufs[i++], bufs[i++], bufs[i++]],
				rand: bufs[i++]
			}
		}
		pbufSrc = createParticleBuffer();
		pbufDst = createParticleBuffer();

		{
			final attribs = ParticleShader.attributes;
			pbufSrcAttributes = [
				new VertexAttribute(pbufSrc.pos, attribs.ipos.location),
				new VertexAttribute(pbufSrc.vel, attribs.ivel.location),
				new VertexAttribute(pbufSrc.mass, attribs.imass.location),
				new VertexAttribute(pbufSrc.gvel[0], attribs.igvel0.location),
				new VertexAttribute(pbufSrc.gvel[1], attribs.igvel1.location),
				new VertexAttribute(pbufSrc.gvel[2], attribs.igvel2.location),
				new VertexAttribute(pbufSrc.deform[0], attribs.ideform0.location),
				new VertexAttribute(pbufSrc.deform[1], attribs.ideform1.location),
				new VertexAttribute(pbufSrc.deform[2], attribs.ideform2.location),
				new VertexAttribute(pbufSrc.jacobian, attribs.ijacobian.location),
				new VertexAttribute(pbufSrc.weights[0], attribs.iweightsX.location),
				new VertexAttribute(pbufSrc.weights[1], attribs.iweightsY.location),
				new VertexAttribute(pbufSrc.weights[2], attribs.iweightsZ.location),
				new VertexAttribute(pbufSrc.rand, attribs.irand.location)
			];
		}
		{
			final attribs = DrawParticleShader.attributes;
			particleBoxes = g.createObject([
				Position(),
				Custom(pbufSrc.pos, attribs.ppos.location, 2),
				Custom(pbufSrc.vel, attribs.pvel.location, 2),
				Custom(pbufSrc.deform[0], attribs.pdeform0.location, 2),
				Custom(pbufSrc.deform[1], attribs.pdeform1.location, 2),
				Custom(pbufSrc.deform[2], attribs.pdeform2.location, 2)
			]);
		}
		{
			final attribs = ScatterMomentumShader.attributes;
			particlePoints = g.createObject([
				Position(),
				Custom(pbufSrc.pos, attribs.ppos.location, 1),
				Custom(pbufSrc.vel, attribs.pvel.location, 1),
				Custom(pbufSrc.mass, attribs.pmass.location, 1),
				Custom(pbufSrc.gvel[0], attribs.pgvel0.location, 1),
				Custom(pbufSrc.gvel[1], attribs.pgvel1.location, 1),
				Custom(pbufSrc.gvel[2], attribs.pgvel2.location, 1),
				Custom(pbufSrc.weights[0], attribs.weightsX.location, 1),
				Custom(pbufSrc.weights[1], attribs.weightsY.location, 1),
				Custom(pbufSrc.weights[2], attribs.weightsZ.location, 1)
			]);
		}
		{
			final attribs = ScatterMeshDataShader.attributes;
			particlePointsMesh = g.createObject([
				Position(),
				Custom(pbufSrc.pos, attribs.ppos.location, 1),
				Custom(pbufSrc.deform[0], attribs.pdeform0.location, 1),
				Custom(pbufSrc.deform[1], attribs.pdeform1.location, 1),
				Custom(pbufSrc.deform[2], attribs.pdeform2.location, 1)
			]);
		}
		velField = g.createObject();
		{
			final attribs = DrawMeshShader.attributes;
			final res = g.createIntVertexBufferInterleaved([4, 4, 4, 3]);
			particleMesh = g.createObject([
				Custom(res.vertexBuffers[0], attribs.posIdx1.location),
				Custom(res.vertexBuffers[1], attribs.posIdx2.location),
				Custom(res.vertexBuffers[2], attribs.norIdx.location),
				Custom(res.vertexBuffers[3], attribs.i3d.location)
			]);
			meshVertexBuffer = res.buffer;
			meshIndexBuffer = particleMesh.index.buffer;
		}
		particleMesh.material.shader = drawMeshShader;

		initBoxes();
		initPoints();
		initPointsMesh();
		initVelField();

		initSim(highSetting);

		inline function getInput(name:String):InputElement {
			return cast Browser.document.getElementById(name);
		}

		final low = getInput("low");
		final med = getInput("medium");
		final high = getInput("high");
		final sup = getInput("super");

		final box = getInput("box");
		final vel = getInput("velocity");

		high.checked = true;

		low.onclick = function():Void {
			initSim(lowSetting);
		}
		med.onclick = function():Void {
			initSim(medSetting);
		}
		high.onclick = function():Void {
			initSim(highSetting);
		}
		sup.onclick = function():Void {
			initSim(superSetting);
		}

		box.onclick = function():Void {
			drawAsBox = box.checked;
		}
		vel.onclick = function():Void {
			drawVelField = vel.checked;
		}

		pot.start();
	}

	function initSim(setting:SimSetting):Void {
		final s = setting;
		currentSetting = s;
		numParticles = s.PARTICLES_W * s.PARTICLES_H * s.PARTICLES_D;

		final uf = BaseShader.uniforms;

		um.set(uf.r2d.res.name, IVec2(s.CELL_TEX_W, s.CELL_TEX_H));
		um.set(uf.r2d.invRes.name, Vec2(1 / s.CELL_TEX_W, 1 / s.CELL_TEX_H));
		um.set(uf.r2d.mask.name, IVec2(s.CELL_TEX_W - 1, s.CELL_TEX_H - 1));
		um.set(uf.r2d.shift.name, IVec2(0, log2(s.CELL_TEX_W)));

		um.set(uf.r3d.res.name, IVec3(s.CELL_TEX_3D_W, s.CELL_TEX_3D_H, s.CELL_TEX_3D_D));
		um.set(uf.r3d.invRes.name, Vec3(1 / s.CELL_TEX_3D_W, 1 / s.CELL_TEX_3D_H, 1 / s.CELL_TEX_3D_D));
		um.set(uf.r3d.mask.name, IVec3(s.CELL_TEX_3D_W - 1, s.CELL_TEX_3D_H - 1, s.CELL_TEX_3D_D - 1));
		um.set(uf.r3d.shift.name, IVec3(0, log2(s.CELL_TEX_3D_W), log2(s.CELL_TEX_3D_W) + log2(s.CELL_TEX_3D_H)));

		um.set(uf.r2dm.res.name, IVec2(s.PARTICLE_TEX_W, s.PARTICLE_TEX_H));
		um.set(uf.r2dm.invRes.name, Vec2(1 / s.PARTICLE_TEX_W, 1 / s.PARTICLE_TEX_H));
		um.set(uf.r2dm.mask.name, IVec2(s.PARTICLE_TEX_W - 1, s.PARTICLE_TEX_H - 1));
		um.set(uf.r2dm.shift.name, IVec2(0, log2(s.PARTICLE_TEX_W)));

		um.set(uf.pdata.particleSize.name, Float(s.PARTICLE_SIZE));
		um.set(uf.pdata.initialVolume.name, Float(s.PARTICLE_SIZE * s.PARTICLE_SIZE * s.PARTICLE_SIZE));

		final wallThickness = (Vec2.of(s.CELL_TEX_3D_W - s.PARTICLES_W * 1.6, s.CELL_TEX_3D_D - s.PARTICLES_D * 1.6) * 0.5).map(x ->
			x < 1 ? 1 : x);
		um.set(ComputeVelocityShader.uniforms.wallThickness.name, IVec3(Std.int(wallThickness.x), 1, Std.int(wallThickness.y)));

		um.set(uf.dt.name, Float(1));

		final colorVec = (Vec3.of(Math.random(), Math.random(), Math.random()) * 0.4 + 0.3) * 24 / s.PARTICLES_W;
		um.set(DrawMeshShader.uniforms.colorVec.name, Vec3(colorVec.x, colorVec.y, colorVec.z));
		um.set(DrawMeshShader.uniforms.boxCenter.name, Vec3(s.PARTICLES_W * 0.5, s.PARTICLES_H * 0.5, s.PARTICLES_D * 0.5));

		um.set(DrawParticleShader.uniforms.boxRes.name, IVec3(s.PARTICLES_W, s.PARTICLES_H, s.PARTICLES_D));

		initParticles();

		if (ctex != null)
			ctex.dispose();
		if (mtex != null)
			mtex.dispose();
		ctex = new RenderTexture(g, s.CELL_TEX_W, s.CELL_TEX_H, Float16, Consts.consts.TEX_COUNT_CELL);
		mtex = new RenderTexture(g, s.PARTICLE_TEX_W, s.PARTICLE_TEX_H, UInt32, Consts.consts.TEX_COUNT_MESH);
	}

	function initShaders():Void {
		final tf:TransformFeedbackOutput = {
			varyings: feedbackVaryings,
			kind: Interleaved
		}
		drawParticleShader = createShader(DrawParticleShader.source);
		drawVelFieldShader = createShader(DrawVelFieldShader.source);
		moveParticleShader = createShader(MoveParticleShader.source, tf);
		preScatterMomentumShader = createShader(PreScatterMomentumShader.source, tf);
		scatterMomentumShader = createShader(ScatterMomentumShader.source);
		computeVelocityShader = createShader(ComputeVelocityShader.source);
		scatterMeshDataShader = createShader(ScatterMeshDataShader.source);
		drawMeshShader = createShader(DrawMeshShader.source);

		renderRGBShader = createShader(RenderRGBShader.source);
		renderAlphaShader = createShader(RenderAlphaShader.source);
	}

	function initParticles():Void {
		final s = currentSetting;
		untyped pbufSrc.buffer.getRawBuffer().id = 0;
		untyped pbufDst.buffer.getRawBuffer().id = 1;
		final d:Array<Float> = [];
		final simCenter = Vec3.of(s.CELL_TEX_3D_W, s.CELL_TEX_3D_H, s.CELL_TEX_3D_D) * 0.5;
		final boxSize = Vec3.of(s.PARTICLES_W, s.PARTICLES_H, s.PARTICLES_D);

		final posvel:Array<Float> = [];

		inline function push(a:Array<Float>, x:Float, y:Float, z:Float):Void {
			a.push(x);
			a.push(y);
			a.push(z);
		}

		final mass = s.PARTICLE_DENSITY * s.PARTICLE_SIZE * s.PARTICLE_SIZE * s.PARTICLE_SIZE;

		for (i in 0...s.PARTICLES_W) {
			for (j in 0...s.PARTICLES_H) {
				for (k in 0...s.PARTICLES_D) {
					final diff = (Vec3.of(i, j, k) + 0.5 - boxSize * 0.5) * s.PARTICLE_SIZE;
					final pos = simCenter + Mat3.rot(Math.PI * 0.0, Vec3.ey) * diff;

					final x = pos.x + (i >> 8);
					final y = (pos.y + (j >> 8)) * 0 + (j + 5) * s.PARTICLE_SIZE;
					final z = pos.z + (k >> 8);

					// final vx = -diff.y * 0.05;
					// final vy = diff.x * 0.05 + 0.2;
					// final vz = diff.z * 0.05 + 0.5;
					final vx = 0;
					final vy = 0;
					final vz = 0;

					// final sign = (i >> 4) * 2 - 1;
					// final x = pos.x + sign * 4;
					// final y = pos.y + sign;
					// final z = pos.z + sign;
					// final vx = -sign * 2;
					// final vy = 0;
					// final vz = 0;

					push(posvel, x, y, z);
					push(posvel, vx, vy, vz);

					push(d, x, y, z);
					push(d, vx, vy, vz);
					d.push(mass);
					// grad vel
					push(d, 0, 0, 0);
					push(d, 0, 0, 0);
					push(d, 0, 0, 0);
					// deform
					push(d, 1, 0, 0);
					push(d, 0, 1, 0);
					push(d, 0, 0, 1);
					// Jacobian
					d.push(1);
					// weights
					push(d, 0, 0, 0);
					push(d, 0, 0, 0);
					push(d, 0, 0, 0);
					// rand
					push(d, Math.random(), Math.random(), Math.random());
				}
			}
		}
		if (d.length != pbufSrc.totalSize * numParticles)
			throw "buffer sizes mismatch";
		pbufSrc.buffer.upload(ArrayBuffer, new Float32Array(d), DynamicCopy);
		pbufDst.buffer.upload(ArrayBuffer, new Float32Array(d), DynamicCopy);

		inline function toIndex(i:Int, j:Int, k:Int):Int {
			return (i * s.PARTICLES_H + j) * s.PARTICLES_D + k;
		}

		particleData = new Float32Array(d);
		mesh = new MeshManager(s.PARTICLES_W, s.PARTICLES_H, s.PARTICLES_D);

		meshQuadCount = 0;
		meshVertexDataIndex = 0;

		final maxQuads = numParticles * 6;
		meshIndexData = new Int32Array(maxQuads * 6);
		meshVertexData = new Int32Array(maxQuads * 60);

		// mpmCpu = new MPMCpu(posvel, CELL_TEX_3D_W, CELL_TEX_3D_H, CELL_TEX_3D_D);
	}

	function flipParticleBuffers():Void {
		inline function flip<A, B:{buffer:A}>(a:B, b:B):Void {
			final tmp = a.buffer;
			a.buffer = b.buffer;
			b.buffer = tmp;
		}
		final n = pbufSrc.vertexBuffers.length;
		flip(pbufSrc, pbufDst);
		for (i in 0...n) {
			flip(pbufSrc.vertexBuffers[i], pbufDst.vertexBuffers[i]);
		}
	}

	function initPoints():Void {
		final obj = particlePoints;
		final w = obj.writer;
		obj.mode = Points;
		for (x in -1...2) {
			for (y in -1...2) {
				w.vertex(x, y, 0);
			}
		}
		w.upload();
		obj.material.shader = scatterMomentumShader;
	}

	function initPointsMesh():Void {
		final obj = particlePointsMesh;
		final w = obj.writer;
		obj.mode = Points;
		w.vertex(0, 0, 0);
		w.upload();
		obj.material.shader = scatterMeshDataShader;
	}

	function initBoxes():Void {
		final obj = particleBoxes;
		final w = obj.writer;
		obj.mode = Triangles;
		final v0 = w.vertex(-1, -1, -1, false);
		final v1 = w.vertex(-1, -1, 1, false);
		final v2 = w.vertex(-1, 1, -1, false);
		final v3 = w.vertex(-1, 1, 1, false);
		final v4 = w.vertex(1, -1, -1, false);
		final v5 = w.vertex(1, -1, 1, false);
		final v6 = w.vertex(1, 1, -1, false);
		final v7 = w.vertex(1, 1, 1, false);
		// -x
		w.index(v1, v2, v0);
		w.index(v1, v3, v2);
		// +x
		w.index(v5, v4, v6);
		w.index(v5, v6, v7);
		// -y
		w.index(v1, v0, v4);
		w.index(v1, v4, v5);
		// +y
		w.index(v3, v7, v6);
		w.index(v3, v6, v2);
		// -z
		w.index(v0, v2, v6);
		w.index(v0, v6, v4);
		// +z
		w.index(v1, v5, v7);
		w.index(v1, v7, v3);
		w.upload();
		obj.material.shader = drawParticleShader;
	}

	function initVelField():Void {
		final obj = velField;
		final w = obj.writer;
		obj.mode = Lines;
		w.vertex(0, 0, 0);
		w.vertex(1.0, 0, 0);
		w.upload();
		obj.material.shader = drawVelFieldShader;
	}

	function createShader(source:Source, ?tfOut:TransformFeedbackOutput):Shader {
		return g.createShader(source.vertex, source.fragment, tfOut);
	}

	function bindTextures():Void {
		um.set(BaseShader.uniforms.ctex.tex.name, Samplers(ctex.data));
		um.set(BaseShader.uniforms.mtex.tex.name, Samplers(mtex.data));
	}

	final BENCHMARK = false;

	function render(shader:Shader, rt:RenderTexture):Void {
		bindTextures();
		g.shader(shader);
		g.blend(None);
		rt.render(!BENCHMARK);
		g.blend();
		g.resetShader();
	}

	function transformFeedback(shader:Shader):Void {
		bindTextures();
		g.transformFeedback(shader, um, pbufSrcAttributes, [pbufDst.buffer], numParticles);
		if (!BENCHMARK)
			flipParticleBuffers();
	}

	function addQuad(p1:Vertex, p2:Vertex, p3:Vertex, p4:Vertex, dim:Int, dir:Int):Void {
		// trace("added");
		p1.groupIndicesListeners.push({
			array: meshVertexData,
			offset: meshVertexDataIndex
		});
		meshVertexDataIndex += 8;
		p1.faceGroupIndicesListeners[dim][dir].push({
			array: meshVertexData,
			offset: meshVertexDataIndex
		});
		meshVertexDataIndex += 4;
		meshVertexData[meshVertexDataIndex++] = p1.cell.idx[0] + p1.dir[0];
		meshVertexData[meshVertexDataIndex++] = p1.cell.idx[1] + p1.dir[1];
		meshVertexData[meshVertexDataIndex++] = p1.cell.idx[2] + p1.dir[2];
		p2.groupIndicesListeners.push({
			array: meshVertexData,
			offset: meshVertexDataIndex
		});
		meshVertexDataIndex += 8;
		p2.faceGroupIndicesListeners[dim][dir].push({
			array: meshVertexData,
			offset: meshVertexDataIndex
		});
		meshVertexDataIndex += 4;
		meshVertexData[meshVertexDataIndex++] = p2.cell.idx[0] + p2.dir[0];
		meshVertexData[meshVertexDataIndex++] = p2.cell.idx[1] + p2.dir[1];
		meshVertexData[meshVertexDataIndex++] = p2.cell.idx[2] + p2.dir[2];
		p3.groupIndicesListeners.push({
			array: meshVertexData,
			offset: meshVertexDataIndex
		});
		meshVertexDataIndex += 8;
		p3.faceGroupIndicesListeners[dim][dir].push({
			array: meshVertexData,
			offset: meshVertexDataIndex
		});
		meshVertexDataIndex += 4;
		meshVertexData[meshVertexDataIndex++] = p3.cell.idx[0] + p3.dir[0];
		meshVertexData[meshVertexDataIndex++] = p3.cell.idx[1] + p3.dir[1];
		meshVertexData[meshVertexDataIndex++] = p3.cell.idx[2] + p3.dir[2];
		p4.groupIndicesListeners.push({
			array: meshVertexData,
			offset: meshVertexDataIndex
		});
		meshVertexDataIndex += 8;
		p4.faceGroupIndicesListeners[dim][dir].push({
			array: meshVertexData,
			offset: meshVertexDataIndex
		});
		meshVertexDataIndex += 4;
		meshVertexData[meshVertexDataIndex++] = p4.cell.idx[0] + p4.dir[0];
		meshVertexData[meshVertexDataIndex++] = p4.cell.idx[1] + p4.dir[1];
		meshVertexData[meshVertexDataIndex++] = p4.cell.idx[2] + p4.dir[2];

		final off = meshQuadCount * 4;
		var idx = meshQuadCount * 6;
		meshIndexData[idx++] = off + 0;
		meshIndexData[idx++] = off + 1;
		meshIndexData[idx++] = off + 2;
		meshIndexData[idx++] = off + 1;
		meshIndexData[idx++] = off + 3;
		meshIndexData[idx++] = off + 2;

		meshQuadCount++;
	}

	function updateMesh():Void {
		final d = particleData;
		final s = currentSetting;
		final distSq = s.PARTICLE_CONNECTION_THRESHOLD * s.PARTICLE_CONNECTION_THRESHOLD;

		inline function disconnected(idx1:Int, idx2:Int):Bool {
			var i1 = idx1 * pbufSrc.totalSize;
			var i2 = idx2 * pbufSrc.totalSize;
			final p1 = Vec3.of(d[i1++], d[i1++], d[i1++]);
			final p2 = Vec3.of(d[i2++], d[i2++], d[i2++]);
			return (p2 - p1).lengthSq > distSq;
		}

		// update connectivity
		for (i in 0...s.PARTICLES_W) {
			for (j in 0...s.PARTICLES_H) {
				for (k in 0...s.PARTICLES_D) {
					final c = mesh.cells[i][j][k];
					if (c.conns[0][1] && (disconnected(c.idx1d, c.adj[0][1].idx1d) || i == s.PARTICLES_W - 1)) {
						mesh.cut(i, j, k, 0, 1);
						{
							final p1 = c.verts[1][1][0];
							final p2 = c.verts[1][1][1];
							final p3 = c.verts[1][0][0];
							final p4 = c.verts[1][0][1];
							addQuad(p1, p2, p3, p4, 0, 1);
						}
						{
							final c = c.adj[0][1];
							final p1 = c.verts[0][0][0];
							final p2 = c.verts[0][0][1];
							final p3 = c.verts[0][1][0];
							final p4 = c.verts[0][1][1];
							addQuad(p1, p2, p3, p4, 0, 0);
						}
					}
					if (c.conns[1][1] && (disconnected(c.idx1d, c.adj[1][1].idx1d) || j == s.PARTICLES_H - 1)) {
						mesh.cut(i, j, k, 1, 1);
						{
							final p1 = c.verts[0][1][1];
							final p2 = c.verts[1][1][1];
							final p3 = c.verts[0][1][0];
							final p4 = c.verts[1][1][0];
							addQuad(p1, p2, p3, p4, 1, 1);
						}
						{
							final c = c.adj[1][1];
							final p1 = c.verts[0][0][0];
							final p2 = c.verts[1][0][0];
							final p3 = c.verts[0][0][1];
							final p4 = c.verts[1][0][1];
							addQuad(p1, p2, p3, p4, 1, 0);
						}
					}
					if (c.conns[2][1] && (disconnected(c.idx1d, c.adj[2][1].idx1d) || k == s.PARTICLES_D - 1)) {
						mesh.cut(i, j, k, 2, 1);
						{
							final p1 = c.verts[1][0][1];
							final p2 = c.verts[1][1][1];
							final p3 = c.verts[0][0][1];
							final p4 = c.verts[0][1][1];
							addQuad(p1, p2, p3, p4, 2, 1);
						}
						{
							final c = c.adj[2][1];
							final p1 = c.verts[0][0][0];
							final p2 = c.verts[0][1][0];
							final p3 = c.verts[1][0][0];
							final p4 = c.verts[1][1][0];
							addQuad(p1, p2, p3, p4, 2, 0);
						}
					}
				}
			}
		}
		if (!mesh.update()) {
			return;
		}

		particleMesh.mode = Triangles;
		meshVertexBuffer.upload(ArrayBuffer, meshVertexData.subarray(0, meshQuadCount * 60), DynamicDraw);
		meshIndexBuffer.upload(ElementArrayBuffer, meshIndexData.subarray(0, meshQuadCount * 6), DynamicDraw);
		// trace("uploaded! quads: " + meshQuadCount);
	}

	function updateRayData():Void {
		prayDir << rayDir;
		final screenPos = Vec2.zero;
		dragging = false;
		var dpress = 0;

		if (input.mouse.hasInput) {
			final mouse = input.mouse;
			screenPos.x = mouse.x;
			screenPos.y = mouse.y;
			dragging = mouse.left;
			dpress = mouse.dleft;
		} else if (input.touches.length > 0) {
			final touch = input.touches[0];
			if (touch.touching) {
				dragging = true;
				screenPos.x = touch.x;
				screenPos.y = touch.y;
				dpress = touch.dtouching;
			}
		}
		screenPos << screenPos / Vec2.of(pot.width, pot.height);
		screenPos.y = 1 - screenPos.y;
		screenPos << screenPos * 2 - 1;

		renderScene(() -> {
			rayPos << g.viewToLocal(Vec3.zero);
			final localPos = g.screenToLocal(screenPos.extend(0));
			rayDir << (localPos - rayPos).normalized;
			if (dpress == 1)
				prayDir << rayDir;
		});
	}

	function renderObject(obj:Object):Void {
		bindTextures();
		obj.rebindAttributes();
		g.drawObject(obj);
	}

	function renderObjectInstanced(obj:Object, count:Int):Void {
		bindTextures();
		obj.rebindAttributes();
		g.drawObjectInstanced(obj, count);
	}

	override function update():Void {
		// trace("begin update");
		final gravity = Vec3.of(0, -0.008, 0);
		um.set(ComputeVelocityShader.uniforms.gravity.name, Vec3(gravity.x, gravity.y, gravity.z));

		if (BENCHMARK) {
			bench();
			return;
		}

		// download particle data
		pbufSrc.buffer.download(0, particleData);

		// update mesh topology
		updateMesh();

		// final st = Timer.stamp();
		transformFeedback(preScatterMomentumShader);
		// pbufSrc.buffer.sync();
		// trace("prescatter " + (Timer.stamp() - st) * 1000);

		// final st = Timer.stamp();
		g.blend(Add);
		g.getRawGL().blendFunc(GL2.ONE, GL2.ONE);
		ctex.render(() -> {
			g.clear(0, 0, 0, 0);
			renderObjectInstanced(particlePoints, numParticles);
		});
		g.blend();
		// ctex.data[0].sync();
		// trace("scatter " + (Timer.stamp() - st) * 1000);

		updateRayData();

		um.set(ComputeVelocityShader.uniforms.rayPos.name, Vec3(rayPos.x, rayPos.y, rayPos.z));
		um.set(ComputeVelocityShader.uniforms.rayDir.name, Vec3(rayDir.x, rayDir.y, rayDir.z));
		um.set(ComputeVelocityShader.uniforms.prayDir.name, Vec3(prayDir.x, prayDir.y, prayDir.z));
		um.set(ComputeVelocityShader.uniforms.dragging.name, Bool(dragging));

		// final st = Timer.stamp();
		render(computeVelocityShader, ctex);
		// ctex.data[0].sync();
		// trace("velocity " + (Timer.stamp() - st) * 1000);

		// final st = Timer.stamp();
		transformFeedback(moveParticleShader);
		// pbufSrc.buffer.sync();
		// trace("move " + (Timer.stamp() - st) * 1000);
	}

	function bench():Void {
		if (frameCount > 10)
			return;

		trace("faster version");
		final st = Timer.stamp();
		for (i in 0...20) {
			transformFeedback(preScatterMomentumShader);
			pbufDst.buffer.sync();
		}
		trace("prescatter " + (Timer.stamp() - st) * 1000);

		final st = Timer.stamp();
		for (i in 0...20) {
			g.blend(Add);
			g.getRawGL().blendFunc(GL2.ONE, GL2.ONE);
			ctex.render(() -> {
				g.clear(0, 0, 0, 0);
				renderObjectInstanced(particlePoints, numParticles);
			});
			g.blend();
			ctex.data[0].sync();
		}
		trace("scatter " + (Timer.stamp() - st) * 1000);

		final st = Timer.stamp();
		for (i in 0...20) {
			render(computeVelocityShader, ctex);
			ctex.data[0].sync();
		}
		trace("velocity " + (Timer.stamp() - st) * 1000);

		final st = Timer.stamp();
		for (i in 0...20) {
			transformFeedback(moveParticleShader);
			pbufDst.buffer.sync();
		}
		trace("move " + (Timer.stamp() - st) * 1000);
	}

	override function draw():Void {
		// trace("begin draw");

		g.screen(pot.width, pot.height);

		g.blend(None);
		mtex.render(() -> {
			g.clearUInt(0, 0, 0, 0);
			renderObjectInstanced(particlePointsMesh, numParticles);
		});
		g.blend();

		renderScene(() -> {
			g.clear(0.6, 0.6, 0.6);
			// g.translate(simCenter);
			// g.rotateY(input.mouse.x * 0.01);
			// g.translate(-simCenter);

			// for (p in mpmCpu.ps) {
			// 	g.pushMatrix();
			// 	g.translate(p.pos);
			// 	g.transform(p.deform.toMat4());
			// 	g.box(PARTICLE_SIZE, PARTICLE_SIZE, PARTICLE_SIZE);
			// 	g.popMatrix();
			// }

			if (drawAsBox)
				renderObjectInstanced(particleBoxes, numParticles * 2);
			else
				renderObjectInstanced(particleMesh, 2);
			if (drawVelField)
				renderObjectInstanced(velField, currentSetting.CELL_TEX_W * currentSetting.CELL_TEX_H);
		});
		// debugDraw();
	}

	function renderScene(f:() -> Void):Void {
		final s = currentSetting;
		g.enableDepthTest();
		final simSize = Vec3.of(s.CELL_TEX_3D_W, s.CELL_TEX_3D_H, s.CELL_TEX_3D_D);
		final boxSize = Vec3.of(s.PARTICLES_W, s.PARTICLES_H, s.PARTICLES_D);
		final simCenter = Vec3.of(simSize.x, boxSize.y, simSize.z) * 0.5;
		g.camera(simCenter + Vec3.ez * Math.max(Math.max(boxSize.x, boxSize.y), boxSize.z) * 1.2 + Vec3.ey * boxSize * 0.3,
			simCenter - Vec3.ey * boxSize * 0.1, Vec3.ey);
		g.inScene(f);
		g.disableDepthTest();
	}

	function debugDraw():Void {
		g.resetCamera();
		g.screen(pot.width, pot.height);
		g.inScene(() -> {
			g.clear(0, 0, 0.5);
			g.shader(renderRGBShader);
			for (i in 0...Consts.consts.TEX_COUNT_CELL) {
				g.texture(ctex.data[i]);
				g.rect(i * 128, 0, 128, 128);
			}
			g.shader(renderAlphaShader);
			for (i in 0...Consts.consts.TEX_COUNT_CELL) {
				g.texture(ctex.data[i]);
				g.rect(i * 128, 128, 128, 128);
			}
			g.shader(renderRGBShader);
			for (i in 0...Consts.consts.TEX_COUNT_MESH) {
				g.texture(mtex.data[i]);
				g.rect(i * 128, 256, 128, 128);
			}
			g.shader(renderAlphaShader);
			for (i in 0...Consts.consts.TEX_COUNT_MESH) {
				g.texture(mtex.data[i]);
				g.rect(i * 128, 384, 128, 128);
			}
			g.resetShader();
		});
	}

	static function main():Void {
		new Main(cast Browser.document.getElementById("canvas"), false, true);
	}
}
