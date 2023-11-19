import hgsl.ShaderModule;
import pot.graphics.gl.shader.DefaultShader;
import pot.graphics.gl.shader.DefaultShaderTextured;
import hgsl.Global.*;
import hgsl.Types;

class Consts extends ShaderModule {
	final TEX_WIDTH_SHIFT:Int = 9;
	final TEX_WIDTH:Int = 1 << TEX_WIDTH_SHIFT;
	final TEX_WIDTH_MASK:Int = TEX_WIDTH - 1;
	final TEX_HEIGHT:Int = 512;
	final TEX_SIZE:IVec2 = ivec2(TEX_WIDTH, TEX_HEIGHT);
	final INV_TEX_SIZE:Vec2 = 1.0 / TEX_SIZE;

	// final HAIR_LENGTH:Float = 4.0;
	final HAIR_DIV_SHIFT:Int = 3;
	final HAIR_DIV:Int = 1 << HAIR_DIV_SHIFT;
	final HAIR_DIV_MASK:Int = HAIR_DIV - 1;
	final INV_HAIR_DIV:Float = 1.0 / (HAIR_DIV - 1);

	// final HAIR_INTERVAL:Float = HAIR_LENGTH * INV_HAIR_DIV;
	final DAMPING:Float = 0.99;
	// final BASE_RADIUS:Float = 5.0;
	// final MAX_RADIUS:Float = BASE_RADIUS + 0.6 * HAIR_LENGTH;
}

class IndexUtil extends ShaderModule {
	function toIndex2(index:Int):IVec2 {
		final idxY = index >> Consts.TEX_WIDTH_SHIFT;
		final idxX = index & Consts.TEX_WIDTH_MASK;
		return ivec2(idxX, idxY);
	}

	function toIndex(uv:Vec2):Int {
		final index2 = ivec2(uv * Consts.TEX_SIZE);
		return index2.y << Consts.TEX_WIDTH_SHIFT | index2.x;
	}
}

class BaseShader extends DefaultShader {
	@uniform var time:Float;
	@uniform var radius:Float;
	@uniform var hairCount:Int;
	@uniform var hairLength:Float;
	@uniform var hairVolume:Float;
	@uniform var pposTex:Sampler2D;
	@uniform var posTex:Sampler2D;
	@uniform var velTex:Sampler2D;
	@uniform var center:Vec3;
	@uniform var rot:Mat3;
}

class SolveShader extends BaseShader {
	@uniform var mode:Int;

	function fragment():Void {
		final index = IndexUtil.toIndex(vTexCoord);
		final hairIndex = index & ~Consts.HAIR_DIV_MASK;
		final i = index & Consts.HAIR_DIV_MASK;
		if ((hairIndex >> Consts.HAIR_DIV_SHIFT) >= hairCount) {
			oColor = texture(posTex, vTexCoord);
			return;
		}
		final hairInterval = hairLength * Consts.INV_HAIR_DIV;
		var i2:Int;
		var len:Float;
		var strength:Float;
		switch (mode) {
			case 0:
				i2 = i ^ 1;
				len = hairInterval;
				strength = 1;
			case 1:
				i2 = ((i + 1) ^ 1) - 1;
				len = hairInterval;
				strength = 1;
			case 2:
				i2 = i ^ 2;
				len = hairInterval * 2;
				strength = 1;
			case 3:
				i2 = ((i + 2) ^ 2) - 2;
				len = hairInterval * 2;
				strength = 1;
		}
		if (i2 < 0 || i2 >= Consts.HAIR_DIV) {
			oColor = texture(posTex, vTexCoord);
			return;
		}
		final index2d1 = IndexUtil.toIndex2(index);
		final index2d2 = IndexUtil.toIndex2(hairIndex | i2);
		final pm1 = texelFetch(posTex, index2d1, 0);
		final invM1 = pm1.w;
		if (invM1 == 0) {
			final root = texelFetch(posTex, IndexUtil.toIndex2(hairIndex), 0).xyz;
			var pm = pm1;
			pm.xyz = normalize(root) * (radius + hairInterval * i);
			oColor = pm;
			return;
		}
		final pm2 = texelFetch(posTex, index2d2, 0);
		final invM2 = pm2.w;
		final p1 = pm1.xyz;
		final p2 = invM2 == 0 ? center + rot * pm2.xyz : pm2.xyz;
		final mass = 1 / (invM1 + invM2);
		final d = p1 - p2;
		final dist2 = dot(d, d);
		final dist = sqrt(dist2);
		final invD = dist > 0 ? 1 / dist : 0;
		final n = d * invD;
		final diff = (len - dist) * mass * strength * 1.7;
		var newPos = p1 + diff * invM1 * n;
		{
			final maxRadius = radius + hairLength * hairVolume;
			final minRadius = mix(radius, maxRadius, i * Consts.INV_HAIR_DIV);
			final delta = newPos - center;
			if (dot(delta, delta) < minRadius * minRadius)
				newPos = center + safeNormalize(delta) * minRadius;
		}
		{
			final maxLength = i * hairInterval;
			final root = center + rot * texelFetch(posTex, IndexUtil.toIndex2(hairIndex), 0).xyz;
			final delta = newPos - root;
			if (dot(delta, delta) > maxLength * maxLength)
				newPos = root + normalize(delta) * maxLength;
		}
		newPos = clamp(newPos, vec3(-25, 0, -25), vec3(25, 50, 25));
		oColor = vec4(newPos, invM1);
	}
}

class CopyShader extends DefaultShader {
	function fragment():Void {
		oColor = texture(material.texture, vTexCoord);
	}
}

class UpdateVelShader extends BaseShader {
	@uniform var gravity:Vec3;

	function fragment():Void {
		final ppm = texture(pposTex, vTexCoord);
		final pm = texture(posTex, vTexCoord);
		final ppos = ppm.xyz;
		final pos = pm.xyz;
		final vel = float(pm.w > 0) * (pos - ppos + gravity);
		oColor = vec4(vel * Consts.DAMPING, 1);
	}
}

class UpdatePosShader extends BaseShader {
	function fragment():Void {
		final pm = texture(posTex, vTexCoord);
		final vel = texture(velTex, vTexCoord).xyz;
		final pos = pm.xyz;
		oColor = vec4(pos + vel, pm.w);
	}
}

class RenderShader extends BaseShader {
	@uniform var rgb:Bool;
	@uniform var color1:Vec3;
	@uniform var color2:Vec3;

	function vertex():Void {
		final index = gl_VertexID + (gl_InstanceID << Consts.HAIR_DIV_SHIFT);
		final index2 = IndexUtil.toIndex2(index);
		final pm = texelFetch(posTex, index2, 0);
		final pos = vec4(pm.w == 0 ? center + rot * pm.xyz : pm.xyz, 1);

		gl_Position = matrix.transform * pos;
		gl_PointSize = 10;

		var t = (index & Consts.HAIR_DIV_MASK) * Consts.INV_HAIR_DIV;
		if (rgb) {
			// FEVER
			final ang = (vec3(-1 / 3.0, 0, 1 / 3.0) + t * t * 0.5 - time * 0.8) * 6.283185307179586;
			vColor = vec4((sin(ang) * 0.5 + 0.5), 1);
		} else {
			t = pow(t, 2.5);

			{
				// top whorl brightness adjustment
				final root = center + rot * texelFetch(posTex, IndexUtil.toIndex2(index & ~Consts.HAIR_DIV_MASK), 0)
					.xyz;
				final end = texelFetch(posTex, IndexUtil.toIndex2(index | Consts.HAIR_DIV_MASK), 0).xyz;
				final n = normalize(root - center);
				final toEnd = end - root;
				final dist = min(1, length(toEnd - dot(toEnd, n) * n) / hairLength * 1.2);
				t = mix(t, 1, pow(max(0, dist * n.y), 4));
			}

			{
				// diffusion
				final hairIndex = index & ~Consts.HAIR_DIV_MASK;
				final i = index & Consts.HAIR_DIV_MASK;
				var i2:Int;
				i2 = i == 0 ? 1 : i - 1;
				final pos2 = texelFetch(posTex, IndexUtil.toIndex2(hairIndex | i2), 0).xyz;
				final tangent = safeNormalize(pos.xyz - pos2);
				final d = dot(tangent, normalize(vec3(-1, -4, -2)));
				t *= sqrt(1 - d * d);
			}

			vColor = vec4(mix(color1, color2, t), 1);
		}
		vPosition = (matrix.modelView * pos).xyz;
		vNormal = matrix.normal * aNormal;
		vTexCoord = aTexCoord;
	}
}

class ColorShader extends DefaultShaderTextured {
	function fragment():Void {
		oColor = vec4(texture(material.texture, vTexCoord).xyz, 1);
	}
}
