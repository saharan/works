import pot.graphics.gl.shader.DefaultShader;
import hgsl.Global.*;
import hgsl.ShaderModule;
import hgsl.ShaderStruct;
import hgsl.Types;

class Res2D extends ShaderStruct {
	var res:IVec2; // (width, height)
	var invRes:Vec2; // (1.0 / width, 1.0 / height)
	var mask:IVec2; // (width - 1, height - 1)
	var shift:IVec2; // (0, log2(width))
}

class Res3D extends ShaderStruct {
	var res:IVec3; // (width, height, depth)
	var invRes:Vec3; // (1 / res)
	var mask:IVec3; // (width - 1, height - 1, depth - 1)
	var shift:IVec3; // (0, log2(width), log2(width) + log2(height))
}

// https://iquilezles.org/articles/distfunctions/
class SdfUtil extends ShaderModule {
	function box(halfExtents:Vec3, p:Vec3):Float {
		final q = abs(p) - halfExtents;
		return length(max(q, 0)) + min(0, max(q.x, max(q.y, q.z)));
	}

	function cylinder(a:Vec3, b:Vec3, r:Float, p:Vec3):Float {
		final ba = b - a;
		final pa = p - a;
		final baba = dot(ba, ba);
		final paba = dot(pa, ba);
		final x = length(pa * baba - ba * paba) - r * baba;
		final y = abs(paba - baba * 0.5) - baba * 0.5;
		final x2 = x * x;
		final y2 = y * y * baba;
		final d = max(x, y) < 0.0 ? -min(x2, y2) : (x > 0.0 ? x2 : 0.0) + (y > 0.0 ? y2 : 0.0);
		return sign(d) * sqrt(abs(d)) / baba;
	}

	function smoothMin(d1:Float, d2:Float, k:Float):Float {
		final h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
		return mix(d2, d1, h) - k * h * (1.0 - h);
	}
}

class GeomUtil extends ShaderModule {
	function nearestPointOnTriangle(c:Vec3, p1:Vec3, p2:Vec3, p3:Vec3):Vec3 {
		final p12 = p2 - p1;
		final p13 = p3 - p1;
		final p1c = c - p1;
		final d1 = dot(p12, p1c);
		final d2 = dot(p13, p1c);
		if (d1 <= 0 && d2 <= 0) { // 1
			return p1;
		}
		final p2c = c - p2;
		final d3 = dot(p12, p2c);
		final d4 = dot(p13, p2c);
		if (d3 >= 0 && d4 <= d3) { // 2
			return p2;
		}
		final v3 = d1 * d4 - d3 * d2;
		if (v3 <= 0 && d1 >= 0 && d3 <= 0) { // 1-2
			final v = d1 / (d1 - d3);
			return p1 + p12 * v;
		}
		final p3c = c - p3;
		final d5 = dot(p12, p3c);
		final d6 = dot(p13, p3c);
		if (d6 >= 0 && d5 <= d6) { // 3
			return p3;
		}
		final v2 = d5 * d2 - d1 * d6;
		if (v2 <= 0 && d2 >= 0 && d6 <= 0) { // 1-3
			final v = d2 / (d2 - d6);
			return p1 + v * p13;
		}
		final v1 = d3 * d6 - d5 * d4;
		final d34 = d4 - d3;
		final d56 = d6 - d5;
		if (v1 <= 0 && d34 >= 0 && d56 <= 0) { // 2-3
			final v = d34 / (d34 - d56);
			return p2 + v * (p3 - p2);
		}
		// 1-2-3
		final denom = 1 / (v1 + v2 + v3);
		return p1 + p12 * (v2 * denom) + p13 * (v3 * denom);
	}
}

class TexUtil extends ShaderModule {
	function toIndex2D(r2d:Res2D, coord:Vec2):IVec2 {
		return ivec2(r2d.res * fract(coord)) & r2d.mask;
	}

	function toIndex3D(r3d:Res3D, coord:Vec3):IVec3 {
		return ivec3(r3d.res * fract(coord)) & r3d.mask;
	}

	function toIndex(r2d:Res2D, i2d:IVec2):Int {
		final index = (i2d & r2d.mask) << r2d.shift;
		return index.x | index.y;
	}

	function toIndex(r3d:Res3D, i3d:IVec3):Int {
		final index = (i3d & r3d.mask) << r3d.shift;
		return index.x | index.y | index.z;
	}

	function toIndex(r2d:Res2D, coord:Vec2):Int {
		return toIndex(r2d, toIndex2D(r2d, coord));
	}

	function toIndex(r3d:Res3D, coord:Vec3):Int {
		return toIndex(r3d, toIndex3D(r3d, coord));
	}

	function toIndex2D(r2d:Res2D, index:Int):IVec2 {
		return ivec2(index) >> r2d.shift & r2d.mask;
	}

	function toIndex3D(r3d:Res3D, index:Int):IVec3 {
		return ivec3(index) >> r3d.shift & r3d.mask;
	}

	function toIndex2D(r2d:Res2D, r3d:Res3D, coord:Vec3):IVec2 {
		return toIndex2D(r2d, toIndex(r3d, coord));
	}

	function toIndex3D(r2d:Res2D, r3d:Res3D, coord:Vec2):IVec3 {
		return toIndex3D(r3d, toIndex(r2d, coord));
	}

	function toIndex2D(r2d:Res2D, r3d:Res3D, i3d:IVec3):IVec2 {
		return toIndex2D(r2d, toIndex(r3d, i3d));
	}

	function toIndex3D(r2d:Res2D, r3d:Res3D, i2d:IVec2):IVec3 {
		return toIndex3D(r3d, toIndex(r2d, i2d));
	}

	function inBoundary(r2d:Res2D, i2d:IVec2, thickness:Int):Bool {
		return any(lessThan(min(i2d, r2d.mask - i2d), ivec2(thickness)));
	}

	function inBoundary(r3d:Res3D, i3d:IVec3, thickness:Int):Bool {
		return any(lessThan(min(i3d, r3d.mask - i3d), ivec3(thickness)));
	}

	function inBoundary(r2d:Res2D, coord:Vec2, thickness:Int):Bool {
		return any(lessThan(min(coord, 1 - coord), thickness * r2d.invRes));
	}

	function inBoundary(r3d:Res3D, coord:Vec3, thickness:Int):Bool {
		return any(lessThan(min(coord, 1 - coord), thickness * r3d.invRes));
	}

	function fetch(r2d:Res2D, tex:Sampler2D, i2d:IVec2):Vec4 {
		return texelFetch(tex, i2d & r2d.mask, 0);
	}

	function fetch(r2d:Res2D, r3d:Res3D, tex:Sampler2D, i3d:IVec3):Vec4 {
		return texelFetch(tex, toIndex2D(r2d, r3d, i3d), 0);
	}

	function fetchLinear(r2d:Res2D, tex:Sampler2D, coord:Vec2):Vec4 {
		final f2d = coord * r2d.res - 0.5;
		final fr = fract(f2d); // fraction of index
		final i1 = ivec2(floor(f2d)) & r2d.mask; // min integer index
		final i2 = (i1 + 1) & r2d.mask; // max integer index
		final txy = texelFetch(tex, ivec2(i1.x, i1.y), 0);
		final txY = texelFetch(tex, ivec2(i1.x, i2.y), 0);
		final tXy = texelFetch(tex, ivec2(i2.x, i1.y), 0);
		final tXY = texelFetch(tex, ivec2(i2.x, i2.y), 0);
		final tx = mix(txy, txY, fr.y);
		final tX = mix(tXy, tXY, fr.y);
		return mix(tx, tX, fr.x);
	}

	function fetchLinear(r2d:Res2D, r3d:Res3D, tex:Sampler2D, coord:Vec3):Vec4 {
		final f3d = coord * r3d.res - 0.5;
		final fr = fract(f3d); // fraction of index
		final i1 = ivec3(floor(f3d)) & r3d.mask; // min integer index
		final i2 = (i1 + 1) & r3d.mask; // max integer index
		final txyz = fetch(r2d, r3d, tex, ivec3(i1.x, i1.y, i1.z));
		final txyZ = fetch(r2d, r3d, tex, ivec3(i1.x, i1.y, i2.z));
		final txYz = fetch(r2d, r3d, tex, ivec3(i1.x, i2.y, i1.z));
		final txYZ = fetch(r2d, r3d, tex, ivec3(i1.x, i2.y, i2.z));
		final tXyz = fetch(r2d, r3d, tex, ivec3(i2.x, i1.y, i1.z));
		final tXyZ = fetch(r2d, r3d, tex, ivec3(i2.x, i1.y, i2.z));
		final tXYz = fetch(r2d, r3d, tex, ivec3(i2.x, i2.y, i1.z));
		final tXYZ = fetch(r2d, r3d, tex, ivec3(i2.x, i2.y, i2.z));
		final txy = mix(txyz, txyZ, fr.z);
		final txY = mix(txYz, txYZ, fr.z);
		final tXy = mix(tXyz, tXyZ, fr.z);
		final tXY = mix(tXYz, tXYZ, fr.z);
		final tx = mix(txy, txY, fr.y);
		final tX = mix(tXy, tXY, fr.y);
		return mix(tx, tX, fr.x);
	}
}

class RenderRGBShader extends DefaultShader {
	function computeBaseColor():Vec4 {
		return vec4(texture(material.texture, vTexCoord).xyz * 5 + 0.5, 1);
	}
}

class RenderAlphaShader extends DefaultShader {
	function computeBaseColor():Vec4 {
		return vec4(texture(material.texture, vTexCoord).www * 5 + 0.5, 1);
	}
}
