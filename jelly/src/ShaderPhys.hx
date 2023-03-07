package;

import ShaderUtil;
import hgsl.Global.*;
import hgsl.ShaderMain;
import hgsl.ShaderModule;
import hgsl.ShaderStruct;
import hgsl.Types;
import pot.graphics.gl.shader.Matrix;

class CommonParticleData extends ShaderStruct {
	var initialVolume:Float;
	var particleSize:Float;
}

class CellData extends ShaderStruct {
	var momentum:Vec3;
	var mass:Float;
	var vel:Vec3;
}

class Consts extends ShaderModule {
	final PI = 3.141592653589793;
	final TEX_COUNT_CELL = 3;
	final TEX_COUNT_MESH = 3;
}

class CellTex extends ShaderStruct {
	var tex:Array<Sampler2D, Consts.TEX_COUNT_CELL>;
}

class MeshTex extends ShaderStruct {
	var tex:Array<USampler2D, Consts.TEX_COUNT_MESH>;
}

// pos: 32-bit float
// deform & normal: 16-bit float
// (pos.x, pos.y, pos.z, deform[0 & 1])
// (deform[2 & 3], deform[4 & 5], deform[6 & 7], deform[8] & normal[0])
// (normal[1 & 2], normal[3 & 4], normal[5 & 6], normal[7 & 8])
class MeshData extends ShaderStruct {
	var pos:Vec3;
	var deform:Mat3;
	var normal:Mat3;
}

class PhysUtil extends ShaderModule {
	function readCellData(tex:CellTex, i2d:IVec2):CellData {
		final v1 = texelFetch(tex.tex[0], i2d, 0);
		final v2 = texelFetch(tex.tex[1], i2d, 0);
		return {
			momentum: vec3(v1.xyz),
			mass: v1.w,
			vel: vec3(v2.xyz)
		}
	}

	function writeCellData(c:CellData):Array<Vec4, Consts.TEX_COUNT_CELL> {
		return [ //
			vec4(c.momentum.xyz, c.mass), //
			vec4(c.vel, 0), //
			vec4(0) //
		];
	}

	function packHalf4x16(v:Vec4):UVec2 {
		return uvec2(packHalf2x16(v.xy), packHalf2x16(v.zw));
	}

	function unpackHalf4x16(v:UVec2):Vec4 {
		return vec4(unpackHalf2x16(v.x), unpackHalf2x16(v.y));
	}

	function readMeshData(tex:MeshTex, i2d:IVec2):MeshData {
		final v1 = texelFetch(tex.tex[0], i2d, 0);
		final v2 = texelFetch(tex.tex[1], i2d, 0);
		final v3 = texelFetch(tex.tex[2], i2d, 0);
		final p1 = unpackHalf2x16(v1.w);
		final p2 = unpackHalf4x16(v2.xy);
		final p3 = unpackHalf4x16(v2.zw);
		final p4 = unpackHalf4x16(v3.xy);
		final p5 = unpackHalf4x16(v3.zw);
		return {
			pos: uintBitsToFloat(v1.xyz),
			deform: mat3(p1, p2, p3.xyz),
			normal: mat3(p3.w, p4, p5)
		}
	}

	function writeMeshData(m:MeshData):Array<UVec4, Consts.TEX_COUNT_MESH> {
		return [
			uvec4(floatBitsToUint(m.pos), packHalf2x16(m.deform[0].xy)),
			uvec4(packHalf4x16(vec4(m.deform[0].z, m.deform[1])), packHalf4x16(vec4(m.deform[2].xyz, m.normal[0].x))),
			uvec4(packHalf4x16(vec4(m.normal[0].yz, m.normal[1].xy)), packHalf4x16(vec4(m.normal[1].z, m.normal[2])))
		];
	}

	function weights(x:Float):Vec3 {
		return vec3(0.5 * (x - 0.5) * (x - 0.5), 0.75 - x * x, 0.5 * (x + 0.5) * (x + 0.5));
	}

	function computeColor(boxCenter:Vec3, colorVec:Vec3, p:Vec3):Vec3 {
		return vec3(0.5, 0.5, 0.5) + sin(vec3(0, 1.0 / 3, -1.0 / 3) * 2 * Consts.PI + colorVec * length(p - boxCenter)) * vec3(0.3, 0.2,
			0.4);
	}

	function lighting(color:Vec3, position:Vec3, normal:Vec3):Vec3 {
		final light = normalize(vec3(1, -2, -3));
		color *= (0.4 + max(0, -dot(normal, light)) * 0.6);

		final eye = normalize(position);
		final refl = eye - 2 * dot(eye, normal) * normal;
		final reflDot = max(0, -dot(light, refl));
		color += pow(reflDot, 5) * 0.4;

		return color;
	}
}

class BaseShader extends ShaderMain {
	@attribute(0) var aPosition:Vec4;
	@attribute(1) var aColor:Vec4;
	@attribute(2) var aNormal:Vec4;
	@attribute(3) var aTexCoord:Vec2;

	@uniform var dt:Float;
	@uniform var matrix:Matrix;
	@uniform var ctex:CellTex;
	@uniform var mtex:MeshTex;
	@uniform var pdata:CommonParticleData;
	@uniform var r2d:Res2D; // cell texture's data
	@uniform var r3d:Res3D; // ... in 3D
	@uniform var r2dm:Res2D; // mesh texture data
	@varying var vTexCoord:Vec2;

	@uniform var colorVec:Vec3;
	@uniform var boxCenter:Vec3;

	function vertex():Void {
		gl_Position = matrix.transform * aPosition;
		vTexCoord = aTexCoord;
	}

	function fragment():Void {
	}
}

class ParticleShader extends ShaderMain {
	@uniform var dt:Float;
	@uniform var ctex:CellTex;
	@uniform var pdata:CommonParticleData;
	@uniform var r2d:Res2D; // cell texture's data
	@uniform var r3d:Res3D; // ... in 3D

	@attribute(0) var ipos:Vec3;
	@attribute(1) var ivel:Vec3;
	@attribute(2) var imass:Float;
	@attribute(3) var igvel0:Vec3;
	@attribute(4) var igvel1:Vec3;
	@attribute(5) var igvel2:Vec3;
	@attribute(6) var ideform0:Vec3;
	@attribute(7) var ideform1:Vec3;
	@attribute(8) var ideform2:Vec3;
	@attribute(9) var ijacobian:Float;
	@attribute(10) var iweightsX:Vec3;
	@attribute(11) var iweightsY:Vec3;
	@attribute(12) var iweightsZ:Vec3;
	@attribute(13) var irand:Vec3;
	@varying var pos:Vec3;
	@varying var vel:Vec3;
	@varying var mass:Float;
	@varying var gvel0:Vec3;
	@varying var gvel1:Vec3;
	@varying var gvel2:Vec3;
	@varying var deform0:Vec3;
	@varying var deform1:Vec3;
	@varying var deform2:Vec3;
	@varying var jacobian:Float;
	@varying var weightsX:Vec3;
	@varying var weightsY:Vec3;
	@varying var weightsZ:Vec3;
	@varying var rand:Vec3;

	function vertex():Void {
	}

	function copyAll():Void {
		pos = ipos;
		vel = ivel;
		mass = imass;
		gvel0 = igvel0;
		gvel1 = igvel1;
		gvel2 = igvel2;
		deform0 = ideform0;
		deform1 = ideform1;
		deform2 = ideform2;
		jacobian = ijacobian;
		weightsX = iweightsX;
		weightsY = iweightsY;
		weightsZ = iweightsZ;
		rand = irand;
	}

	function fragment():Void {
	}
}

class PreScatterMomentumShader extends ParticleShader {
	function vertex():Void {
		copyAll();
		final fpos = fract(pos) - 0.5;
		weightsX = PhysUtil.weights(fpos.x);
		weightsY = PhysUtil.weights(fpos.y);
		weightsZ = PhysUtil.weights(fpos.z);

		// Neo-Hookean model
		final totalScale = 0.125;
		final MU = 1.0;
		final LAMBDA = 1.0;
		final deform = mat3(ideform0, ideform1, ideform2);
		final deformT = transpose(deform);
		final J = ijacobian;

		// First Piola–Kirchhoff stress
		// final deformInvT = inverse(deformT);
		// final firstPK = MU * (deform - deformInvT) + LAMBDA * log(J) * deformInvT;
		// Cauchey stress
		// final sigma = 1 / J * firstPK * deformT;
		// final volume = J * pdata.initialVolume;
		// final gmomentum = mat3(igvel0, igvel1, igvel2) * imass - totalScale * dt * volume * 4 * sigma;

		// faster one
		final sigmaVol = (MU * (deform * deformT - mat3(1)) + LAMBDA * log(J) * mat3(1)) * pdata.initialVolume;
		final gmomentum = mat3(igvel0, igvel1, igvel2) * imass - totalScale * dt * 4 * sigmaVol;

		gvel0 = gmomentum[0];
		gvel1 = gmomentum[1];
		gvel2 = gmomentum[2];
	}

	function fragment():Void {
	}
}

class ScatterMomentumShader extends BaseShader {
	@attribute(4) var ppos:Vec3;
	@attribute(5) var pvel:Vec3;
	@attribute(6) var pmass:Float;
	@attribute(7) var pgvel0:Vec3; // this is actually grad momentum this time
	@attribute(8) var pgvel1:Vec3;
	@attribute(9) var pgvel2:Vec3;
	@attribute(10) var weightsX:Vec3;
	@attribute(11) var weightsY:Vec3;
	@attribute(12) var weightsZ:Vec3;
	@varying var vColors:Array<Vec4, 3>;
	@color var oColors:Array<Vec4, Consts.TEX_COUNT_CELL>;

	function vertex():Void {
		var ipos = ivec3(aPosition);

		final weight = weightsX[ipos.x + 1] * weightsY[ipos.y + 1];
		final ci3d = ivec3(floor(ppos)) + ipos;
		final cpos = ci3d + 0.5;
		final pdiff = cpos - ppos;
		final momentum = pvel * pmass + mat3(pgvel0, pgvel1, pgvel2) * pdiff;

		final base = vec4(momentum, pmass) * weight;
		final zdiff = vec4(pgvel2 * weight, 0);
		vColors[0] = (base - zdiff) * weightsZ[0];
		vColors[1] = base * weightsZ[1];
		vColors[2] = (base + zdiff) * weightsZ[2];

		final ci2d = TexUtil.toIndex2D(r2d, r3d, ci3d);
		gl_Position = vec4((ci2d + 0.5) * r2d.invRes * 2 - 1, 0, 1);
		gl_PointSize = 1;
	}

	function fragment():Void {
		oColors = vColors;
	}
}

class ComputeVelocityShader extends BaseShader {
	@uniform var gravity:Vec3;

	@uniform var rayPos:Vec3;
	@uniform var rayDir:Vec3;
	@uniform var prayDir:Vec3;
	@uniform var dragging:Bool;
	@uniform var wallThickness:IVec3;

	@color var outColors:Array<Vec4, Consts.TEX_COUNT_CELL>;
	var c:CellData;
	var i3d:IVec3;

	function fragment():Void {
		i3d = TexUtil.toIndex3D(r2d, r3d, vTexCoord);

		// dz = -1
		final momentumMass1 = TexUtil.fetch(r2d, r3d, ctex.tex[0], i3d + ivec3(0, 0, 1));
		// dz = 0
		final momentumMass2 = TexUtil.fetch(r2d, r3d, ctex.tex[1], i3d);
		// dz = 1
		final momentumMass3 = TexUtil.fetch(r2d, r3d, ctex.tex[2], i3d - ivec3(0, 0, 1));

		final momentumMass = momentumMass1 + momentumMass2 + momentumMass3;
		c = {
			momentum: momentumMass.xyz,
			mass: momentumMass.w,
			vel: vec3(0)
		}
		cellMain();
		outColors = PhysUtil.writeCellData(c);
	}

	function and(a:BVec3, b:BVec3):BVec3 {
		return bvec3(ivec3(a) & ivec3(b));
	}

	function cellMain():Void {
		c.momentum += c.mass * gravity * dt;
		if (c.mass > 1e-6)
			c.vel = c.momentum / c.mass;
		else
			c.vel = vec3(0);

		if (dragging) {
			final wpos = i3d + 0.5;
			final nearestPoint = GeomUtil.nearestPointOnTriangle(wpos, rayPos, rayPos + rayDir * 100, rayPos + prayDir * 100);
			if (length(nearestPoint - wpos) < 2.0) {
				final dist = length(nearestPoint - rayPos);
				final diff = dist * (rayDir - prayDir);
				c.vel = diff / dt;
			}
		}

		c.vel = clamp(c.vel * dt, vec3(-1), vec3(1)) / dt;

		final i3d = TexUtil.toIndex3D(r2d, r3d, vTexCoord);

		// free slip BC
		final negBound = and(lessThanEqual(i3d, wallThickness), lessThan(c.vel, vec3(0)));
		c.vel = mix(c.vel, vec3(0), negBound);
		final posBound = and(greaterThanEqual(i3d, r3d.mask - wallThickness), greaterThan(c.vel, vec3(0)));
		c.vel = mix(c.vel, vec3(0), posBound);

		// no slip BC
		// if (TexUtil.inBoundary(r3d, i3d, thickness + 1)) {
		// 	c.vel = vec3(0);
		// }

		// if (i3d.y <= thickness) {
		// 	c.vel = vec3(0);
		// 	final v = (r3d.invRes * i3d).xz - 0.5;
		// 	c.vel.xz = vec2(-v.y, v.x) * 0.5;
		// }
		// if (i3d.y > 20) {
		// 	c.vel = vec3(0);
		// }
	}
}

class MoveParticleShader extends ParticleShader {
	function vertex():Void {
		copyAll();

		vel = vec3(0);
		var gvel = mat3(0);

		final i3d = TexUtil.toIndex3D(r3d, ipos * r3d.invRes);
		for (di in -1...2) {
			for (dj in -1...2) {
				for (dk in -1...2) {
					final c3d = i3d + ivec3(di, dj, dk);
					final cvel = TexUtil.fetch(r2d, r3d, ctex.tex[1], c3d).xyz;
					final weight = iweightsX[di + 1] * iweightsY[dj + 1] * iweightsZ[dk + 1];
					final cpos = c3d + 0.5;
					final d = cpos - ipos;
					final wvel = cvel * weight;
					vel += wvel;
					gvel += outerProduct(wvel, d);
				}
			}
		}
		gvel *= 4.0;

		final deform = mat3(ideform0, ideform1, ideform2);
		var newDeform = deform + gvel * deform * dt;
		jacobian = determinant(newDeform);
		if (jacobian < 0.05 || jacobian > 20.0) {
			jacobian = 1;
			newDeform = mat3(1);
			gvel = mat3(0);
		}

		gvel0 = gvel[0];
		gvel1 = gvel[1];
		gvel2 = gvel[2];

		deform0 = newDeform[0];
		deform1 = newDeform[1];
		deform2 = newDeform[2];

		var newPos = clamp(ipos + vel * dt, vec3(1 + irand * 0.0001), vec3(r3d.mask - irand * 0.0001));
		var newVel = (newPos - ipos) / dt;

		pos = newPos;
		vel = newVel;
	}

	function fragment():Void {
	}
}

class ScatterMeshDataShader extends BaseShader {
	@attribute(4) var ppos:Vec3;
	@attribute(5) var pdeform0:Vec3;
	@attribute(6) var pdeform1:Vec3;
	@attribute(7) var pdeform2:Vec3;
	@varying(flat) var vColors:Array<UVec4, Consts.TEX_COUNT_MESH>;
	@color var oColors:Array<UVec4, Consts.TEX_COUNT_MESH>;

	function vertex():Void {
		final deform = mat3(pdeform0, pdeform1, pdeform2);
		final nmat = inverse(transpose(deform));
		var mesh:MeshData = {
			pos: ppos,
			deform: deform,
			normal: mat3(normalize(nmat[0]), normalize(nmat[1]), normalize(nmat[2]))
		}
		vColors = PhysUtil.writeMeshData(mesh);

		final i2d = TexUtil.toIndex2D(r2dm, gl_InstanceID);
		gl_Position = vec4((i2d + 0.5) * r2dm.invRes * 2 - 1, 0, 1);
		gl_PointSize = 1;
	}

	function fragment():Void {
		oColors = vColors;
	}
}

class DrawParticleShader extends BaseShader {
	@attribute(4) var ppos:Vec3;
	@attribute(5) var pvel:Vec3;
	@attribute(6) var pdeform0:Vec3;
	@attribute(7) var pdeform1:Vec3;
	@attribute(8) var pdeform2:Vec3;
	@uniform var boxRes:IVec3;
	@varying var shadow:Float;
	@varying var vPosition:Vec3;
	@varying var vOrigPosition:Vec3;
	@color var oColor:Vec4;

	function vertex():Void {
		final deform = mat3(pdeform0, pdeform1, pdeform2);
		var pos = vec4(deform * aPosition.xyz * pdata.particleSize * 0.5 * 1.0 + ppos, 1);
		if ((gl_InstanceID & 1) == 1)
			pos.y = 2;
		vPosition = (matrix.modelView * pos).xyz;
		final i3d = ivec3(gl_InstanceID >> 1) / ivec3(boxRes.y * boxRes.z, boxRes.z, 1) % boxRes;
		vOrigPosition = i3d + 0.5 + aPosition.xyz * 0.5;
		gl_Position = matrix.transform * pos;
		shadow = gl_InstanceID & 1;
	}

	function fragment():Void {
		if (shadow > 0.5) {
			oColor = vec4(0.2, 0.2, 0.2, 1);
		} else {
			final dx = dFdx(vPosition.xyz);
			final dy = dFdy(vPosition.xyz);
			final n = normalize(cross(dx, dy));
			oColor = vec4(PhysUtil.lighting(PhysUtil.computeColor(boxCenter, colorVec, vOrigPosition), vPosition, n), 1);
		}
	}
}

class DrawVelFieldShader extends BaseShader {
	@varying var vColor:Vec4;
	@color var oColor:Vec4;

	function vertex():Void {
		final i3d = TexUtil.toIndex3D(r3d, gl_InstanceID);
		final i2d = TexUtil.toIndex2D(r2d, r3d, i3d);
		final c = PhysUtil.readCellData(ctex, i2d);
		final scale = aPosition.x * 5.0;
		final pos = vec4(i3d + 0.5 + c.vel * scale, 1);
		gl_Position = matrix.transform * pos;
		final alpha = c.mass * 2.0;
		vColor = vec4(1, 1, 1, alpha);
	}

	function fragment():Void {
		oColor = vColor;
	}
}

class DrawMeshShader extends ShaderMain {
	@attribute(0) var posIdx1:IVec4;
	@attribute(1) var posIdx2:IVec4;
	@attribute(2) var norIdx:IVec4;
	@attribute(3) var i3d:IVec3;

	@uniform var matrix:Matrix;
	@uniform var mtex:MeshTex;
	@uniform var pdata:CommonParticleData;
	@uniform var r2dm:Res2D; // mesh texture data

	@uniform var colorVec:Vec3;
	@uniform var boxCenter:Vec3;

	@varying var vPosition:Vec3;
	@varying var vNormal:Vec3;
	@varying var vColor:Vec3;
	@color var oColor:Vec4;
	@varying var shadow:Float;

	function posWeight(idx:Int):Vec4 {
		if (idx == -1)
			return vec4(0);
		final v = PhysUtil.readMeshData(mtex, TexUtil.toIndex2D(r2dm, idx >> 3));
		final diff = ((ivec3(idx) >> ivec3(0, 1, 2) & 1) << 1) - 1.0;
		return vec4(v.pos + v.deform * diff * pdata.particleSize * 0.5, 1);
	}

	function norWeight(idx:Int):Vec4 {
		if (idx == -1)
			return vec4(0);
		final v = PhysUtil.readMeshData(mtex, TexUtil.toIndex2D(r2dm, idx >> 3));
		return vec4(v.normal[idx & 3] * ((idx >> 1 & 2) - 1), 1);
	}

	function vertex():Void {
		final vp = posWeight(posIdx1.x) + posWeight(posIdx1.y) + posWeight(posIdx1.z) + posWeight(posIdx1.w) + posWeight(posIdx2.x) +
			posWeight(posIdx2.y) + posWeight(posIdx2.z) + posWeight(posIdx2.w);
		var p = vec4(vp.xyz / vp.w, 1);

		if (gl_InstanceID == 1) {
			p.y = 2;
			gl_Position = matrix.transform * p;
			vPosition = (matrix.modelView * p).xyz;
			vNormal = vec3(0, 1, 0);
			shadow = 1;
		} else {
			final vn = norWeight(norIdx.x) + norWeight(norIdx.y) + norWeight(norIdx.z) + norWeight(norIdx.w);
			final n = vn.xyz / vn.w;
			gl_Position = matrix.transform * p;
			vPosition = (matrix.modelView * p).xyz;
			vNormal = normalize(matrix.normal * n);
			vColor = PhysUtil.computeColor(boxCenter, colorVec, i3d);
			shadow = 0;
		}
	}

	function fragment():Void {
		if (shadow > 0.5) {
			oColor = vec4(0.2, 0.2, 0.2, 1);
		} else {
			oColor = vec4(PhysUtil.lighting(vColor, vPosition, normalize(vNormal)), 1);
		}
	}
}
