import pot.graphics.gl.shader.DefaultShader;
import hgsl.ShaderMain;
import hgsl.ShaderStruct;
import hgsl.Global.*;
import hgsl.Types;
import hgsl.ShaderModule;

class ResInfo extends ShaderStruct {
	var res2:Int; // resolution in 2D
	var res3:Int; // resolution in 3D
	var invRes2:Float; // 1.0 / res2
	var invRes3:Float; // 1.0 / res3
	var shift2:IVec2; // (0, log2(res2))
	var shift3:IVec3; // (0, log2(res3), 2 * log2(res3))
	var mask2:Int; // res2 - 1
	var mask3:Int; // res3 - 1
}

class Tex3D extends ShaderModule {
	function uvToIndex3D(resInfo:ResInfo, uv:Vec2):IVec3 {
		final tmp = ivec2(uv * resInfo.res2) << resInfo.shift2;
		final index = tmp.x | tmp.y;
		return ivec3(index) >> resInfo.shift3 & resInfo.mask3;
	}

	function index3DTo2D(resInfo:ResInfo, i3d:IVec3):IVec2 {
		final tmp = (i3d & resInfo.mask3) << resInfo.shift3;
		final index = tmp.x | tmp.y | tmp.z;
		return ivec2(index) >> resInfo.shift2 & resInfo.mask2;
	}

	function fetch3D(resInfo:ResInfo, tex:Sampler2D, i3d:IVec3):Vec4 {
		return texelFetch(tex, index3DTo2D(resInfo, i3d), 0);
	}

	function trilinear(resInfo:ResInfo, tex:Sampler2D, p:Vec3):Vec4 {
		final f3d = p * resInfo.res3 - 0.5;
		final fr = fract(f3d); // fraction of index
		final i1 = ivec3(floor(f3d)) & resInfo.mask3; // min integer index
		final i2 = (i1 + 1) & resInfo.mask3; // max integer index
		final txyz = fetch3D(resInfo, tex, ivec3(i1.x, i1.y, i1.z));
		final txyZ = fetch3D(resInfo, tex, ivec3(i1.x, i1.y, i2.z));
		final txYz = fetch3D(resInfo, tex, ivec3(i1.x, i2.y, i1.z));
		final txYZ = fetch3D(resInfo, tex, ivec3(i1.x, i2.y, i2.z));
		final tXyz = fetch3D(resInfo, tex, ivec3(i2.x, i1.y, i1.z));
		final tXyZ = fetch3D(resInfo, tex, ivec3(i2.x, i1.y, i2.z));
		final tXYz = fetch3D(resInfo, tex, ivec3(i2.x, i2.y, i1.z));
		final tXYZ = fetch3D(resInfo, tex, ivec3(i2.x, i2.y, i2.z));
		final txy = mix(txyz, txyZ, fr.z);
		final txY = mix(txYz, txYZ, fr.z);
		final tXy = mix(tXyz, tXyZ, fr.z);
		final tXY = mix(tXYz, tXYZ, fr.z);
		final tx = mix(txy, txY, fr.y);
		final tX = mix(tXy, tXY, fr.y);
		return mix(tx, tX, fr.x);
	}
}

class AdvectUtil extends ShaderModule {
	function advect(resInfo:ResInfo, velTex:Sampler2D, tex:Sampler2D, uv:Vec2, velScale:Float):Vec4 {
		final i3d = Tex3D.uvToIndex3D(resInfo, uv);
		final vel = texture(velTex, uv).xyz;
		var p = (i3d + 0.5 - vel * velScale) * resInfo.invRes3;
		return Tex3D.trilinear(resInfo, tex, p);
	}

	function advectMacCormack(resInfo:ResInfo, velTex:Sampler2D, tex1:Sampler2D, tex2:Sampler2D, uv:Vec2, mask:Vec4):Vec4 {
		final v1 = texture(tex1, uv);
		final v2 = texture(tex2, uv);
		final error = 0.5 * (v2 - v1);
		return advect(resInfo, velTex, tex1, uv, 1.0) - error * mask;
	}
}

class BaseShader extends DefaultShader {
	@uniform var resInfo:ResInfo;

	@uniform var texVelVof:Sampler2D;
	@uniform var texDivPrsWgt:Sampler2D;
	@uniform var texAdvectTmp:Sampler2D;

	@uniform var radius:Float;
	@uniform var center:Vec3;
	@uniform var pcenter:Vec3;
	@uniform var power:Float;
	@uniform var ventilation:Float;
	@uniform var vorticity:Float;
	@uniform var time:Float;

	var i3d:IVec3;
	var p:Vec3;

	function safeNormalize(v:Vec3):Vec3 {
		final l2 = dot(v, v);
		return l2 == 0 ? vec3(0) : v * inversesqrt(l2);
	}

	function vertex():Void {
		gl_Position = matrix.transform * aPosition;
		vTexCoord = aTexCoord;
	}

	function fragment():Void {
		i3d = Tex3D.uvToIndex3D(resInfo, vTexCoord);
		p = (i3d + 0.5) * resInfo.invRes3;
	}
}

class InitVofShader extends BaseShader {
	function fragment():Void {
		super.fragment();
		oColor = vec4(0);
	}
}

class AdvectPredictShader extends BaseShader {
	@uniform var forward:Bool;

	function fragment():Void {
		super.fragment();
		if (forward) {
			oColor = AdvectUtil.advect(resInfo, texVelVof, texVelVof, vTexCoord, 1.0); // forward
		} else {
			oColor = AdvectUtil.advect(resInfo, texVelVof, texAdvectTmp, vTexCoord, -1.0); // backward
		}
	}
}

class AdvectCorrectShader extends BaseShader {
	function fragment():Void {
		super.fragment();
		final uv = vTexCoord;
		final isWall = any(lessThan(min(p, 1 - p), vec3(2 * resInfo.invRes3)));
		final mask = vec4(0, 0, 0, float(isWall));
		var res = AdvectUtil.advectMacCormack(resInfo, texVelVof, texVelVof, texAdvectTmp, uv, mask);
		res.w = clamp(res.w, 0.0, 1.0);
		final factor = vec4(1, 1, 1, 0.995);
		res *= factor;
		if (!isWall) {
			final p1 = pcenter;
			final p2 = center;
			final diff = p2 - p1;
			final diff2 = dot(diff, diff);
			var nearest:Vec3;
			if (diff2 == 0) {
				nearest = p2;
			} else {
				var t = dot(p - p1, diff);
				t = clamp(t, 0.0, diff2) / diff2;
				nearest = mix(p1, p2, t);
			}
			final l = length(nearest - p);
			final vel = (p2 - p1) * resInfo.res3 * 0.5;
			if (l < radius) {
				final ang = time * 2.0;
				final ang2 = time * 1.7;
				res.xyz = (vec3(0, 1.0 * (sin(ang2) * 0.5 + 1.0), 0) + vec3(cos(ang), 0, sin(ang)) * 0.4) * power;
				res.w = 1.0;
			}
			if (l < radius * 1.2) {
				res.xyz += vel;
			}
			res.y -= res.w * clamp((p.y - 0.3) * 0.1, 0, 0.1);
		}
		final flow = 0.5 * ventilation * (p.y - 0.5) * normalize(0.5 - p.xz);
		if (any(lessThan(min(p.xz, 1.0 - p.xz), vec2(resInfo.invRes3)))) {
			res.xz = flow;
		}
		oColor = res;
	}
}

class VorticityConfinementShader extends BaseShader {
	function curl(i3d:IVec3):Vec3 {
		final d = ivec2(1, 0);
		final x1 = Tex3D.fetch3D(resInfo, texVelVof, i3d - d.xyy).xyz;
		final x2 = Tex3D.fetch3D(resInfo, texVelVof, i3d + d.xyy).xyz;
		final y1 = Tex3D.fetch3D(resInfo, texVelVof, i3d - d.yxy).xyz;
		final y2 = Tex3D.fetch3D(resInfo, texVelVof, i3d + d.yxy).xyz;
		final z1 = Tex3D.fetch3D(resInfo, texVelVof, i3d - d.yyx).xyz;
		final z2 = Tex3D.fetch3D(resInfo, texVelVof, i3d + d.yyx).xyz;
		return 0.5 * vec3((y2.z - y1.z) - (z2.y - z1.y), (z2.x - z1.x) - (x2.z - x1.z), (x2.y - x1.y) - (y2.x - y1.x));
	}

	function curlDir(i3d:IVec3):Vec3 {
		final d = ivec2(1, 0);
		final x1 = length(curl(i3d - d.xyy));
		final x2 = length(curl(i3d + d.xyy));
		final y1 = length(curl(i3d - d.yxy));
		final y2 = length(curl(i3d + d.yxy));
		final z1 = length(curl(i3d - d.yyx));
		final z2 = length(curl(i3d + d.yyx));
		return safeNormalize(vec3(x2 - x1, y2 - y1, z2 - z1));
	}

	function fragment():Void {
		super.fragment();
		var res = texture(texVelVof, vTexCoord);
		if (any(greaterThan(abs(p * 2 - 1), vec3(0.95)))) {
			// do not confine near boundaries
			oColor = res;
			return;
		}
		res.xyz += vorticity * cross(curlDir(i3d), curl(i3d));
		oColor = res;
	}
}

class ComputeDivShader extends BaseShader {
	function fragment():Void {
		super.fragment();
		final prs = texture(texDivPrsWgt, vTexCoord).y * 0.9; // warm starting
		final d = ivec2(1, 0);
		var div = 0.0;
		div -= Tex3D.fetch3D(resInfo, texVelVof, i3d - d.xyy).x;
		div += Tex3D.fetch3D(resInfo, texVelVof, i3d + d.xyy).x;
		div -= Tex3D.fetch3D(resInfo, texVelVof, i3d - d.yxy).y;
		div += Tex3D.fetch3D(resInfo, texVelVof, i3d + d.yxy).y;
		div -= Tex3D.fetch3D(resInfo, texVelVof, i3d - d.yyx).z;
		div += Tex3D.fetch3D(resInfo, texVelVof, i3d + d.yyx).z;
		final weight = any(lessThan(min(p, 1.0 - p), vec3(resInfo.invRes3))) ? 0.0 : 1.0;
		oColor = vec4(div, prs, weight, 1);
	}
}

class SolvePoissonShader extends BaseShader {
	@uniform var parity:Int;

	function fragment():Void {
		super.fragment();
		if (((i3d.x ^ i3d.y ^ i3d.z ^ parity) & 1) == 0) {
			oColor = texture(texDivPrsWgt, vTexCoord);
		} else {
			final d = ivec2(1, 0);
			var res = texture(texDivPrsWgt, vTexCoord);
			var nd = vec2(-res.x, 0);

			var pw:Vec2;
			pw = Tex3D.fetch3D(resInfo, texDivPrsWgt, i3d - d.xyy).yz;
			nd += vec2(pw.x * pw.y, pw.y);
			pw = Tex3D.fetch3D(resInfo, texDivPrsWgt, i3d + d.xyy).yz;
			nd += vec2(pw.x * pw.y, pw.y);
			pw = Tex3D.fetch3D(resInfo, texDivPrsWgt, i3d - d.yxy).yz;
			nd += vec2(pw.x * pw.y, pw.y);
			pw = Tex3D.fetch3D(resInfo, texDivPrsWgt, i3d + d.yxy).yz;
			nd += vec2(pw.x * pw.y, pw.y);
			pw = Tex3D.fetch3D(resInfo, texDivPrsWgt, i3d - d.yyx).yz;
			nd += vec2(pw.x * pw.y, pw.y);
			pw = Tex3D.fetch3D(resInfo, texDivPrsWgt, i3d + d.yyx).yz;
			nd += vec2(pw.x * pw.y, pw.y);

			nd.y = max(1.0, nd.y);

			final np = nd.x / nd.y;
			final delta = np - res.y;
			res.y += delta * 1.3; // SOR
			oColor = res;
		}
	}
}

class ApplyPressureShader extends BaseShader {
	function pressureAt(orig:Float, i3d:IVec3):Float {
		final pw = Tex3D.fetch3D(resInfo, texDivPrsWgt, i3d).yz;
		return mix(orig, pw.x, pw.y);
	}

	function fragment():Void {
		super.fragment();
		final d = ivec2(1, 0);
		final pw = texture(texDivPrsWgt, vTexCoord).yz;
		var res = texture(texVelVof, vTexCoord);
		if (pw.y == 0) { // Neumann BC
			res.w = 0;
		} else {
			final p = pw.x;
			final delta = -0.5 * vec3( //
				pressureAt(p, i3d + d.xyy)
				- pressureAt(p, i3d - d.xyy), //
				pressureAt(p, i3d + d.yxy)
				- pressureAt(p, i3d - d.yxy), //
				pressureAt(p, i3d + d.yyx)
				- pressureAt(p, i3d - d.yyx) //
			);
			res.xyz += delta;
		}
		oColor = res;
	}
}

class RenderShader extends BaseShader {
	@uniform var camPos:Vec3;
	@uniform var halfExtent:Float;

	function vertex():Void {
		gl_Position = matrix.transform * aPosition;
		vPosition = (matrix.model * aPosition).xyz;
	}

	function worldToLocal(p:Vec3):Vec3 {
		return (p + halfExtent) / (2.0 * halfExtent);
	}

	function outOfBounds(p:Vec3):Bool {
		return any(greaterThan(abs(p) - halfExtent, vec3(0)));
	}

	function fragment():Void {
		var p = vPosition;
		final dir = normalize(p - camPos);
		final step = 0.1;
		p += dir * step * fract(sin(dot(p + fract(time), vec3(619.394, 487.196, 543.913))) * 47921.637);
		var alpha = 0.0;
		for (i in 0...1000) {
			if (outOfBounds(p)) {
				break;
			}
			final local = worldToLocal(p);
			var dens = Tex3D.trilinear(resInfo, texVelVof, local).w;
			final depth = radius * 1.5 - length(local - center);
			if (depth > 0) {
				dens += depth * 20;
			}
			alpha += dens * 0.2;
			p += dir * step;
		}
		final ex = 1 + max(0, alpha - 1) * 0.5;
		alpha = min(1, alpha);
		oColor = vec4(vec3(0.8, 0.9, 1.0) * ex, alpha);
	}
}

class DebugShader extends BaseShader {
	function transformUV(uv:Vec2):Vec2 {
		final i3d = Tex3D.uvToIndex3D(resInfo, uv);
		final unitX = i3d.z / 8;
		final unitY = i3d.z % 8;
		final i2d = ivec2(i3d.x + unitX * resInfo.res3, i3d.y + unitY * resInfo.res3);
		return (i2d + 0.5) * resInfo.invRes2;
	}

	function fragment():Void {
		var uv = vTexCoord;
		uv *= 2.0;
		if (uv.y > 1.0) {
			if (uv.x < 1.0) {
				// vel
				oColor = vec4(texture(texVelVof, transformUV(fract(uv))).xyz * 0.5 + 0.5, 1);
			} else {
				// vof
				oColor = vec4(texture(texVelVof, transformUV(fract(uv))).www, 1);
			}
		} else {
			if (uv.x < 1.0) {
				// div
				oColor = vec4(texture(texDivPrsWgt, transformUV(fract(uv))).xxx + 0.5, 1);
			} else {
				// prs
				oColor = vec4(texture(texDivPrsWgt, transformUV(fract(uv))).yyy + 0.5, 1);
			}
		}
	}
}
