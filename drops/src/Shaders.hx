import hgsl.Global.*;
import hgsl.ShaderModule;
import hgsl.Types;
import pot.graphics.gl.shader.DefaultShader;

class EquirectangularTools extends ShaderModule {
	final PI = 3.141592653589793;
	final TWO_PI = PI * 2.0;

	function atan2(y:Float, x:Float):Float {
		return x == 0.0 ? sign(y) * PI * 0.5 : atan(y, x);
	}

	function sampleTexture(tex:Sampler2D, vec:Vec3):Vec3 {
		final uv = vec2(atan2(vec.z, vec.x) / TWO_PI + 0.5, 1 - acos(vec.y) / PI);
		return texture(tex, uv.xy).xyz;
	}
}

class BaseShader extends DefaultShader {
	final BACK_NORMAL_MIX = 0.2;
	final REFRACTION_INDEX = 0.7;
	final BACK_NORMAL_MIX_CAUSTICS = 0.3;
	final REFRACTION_INDEX_CAUSTICS = 0.5;
	@uniform var env:Sampler2D;
	@uniform var spectrum:Sampler2D;
	@uniform var back:Sampler2D;
	@uniform var front:Sampler2D;
	@uniform var lightBack:Sampler2D;
	@uniform var lightFront:Sampler2D;
	@uniform var caustics:Sampler2D;
	@uniform var invLightView:Mat4;
	@uniform var time:Float;
	@uniform var groundY:Float;
	@uniform var groundSize:Float;
}

class DepthShader extends BaseShader {
	function vertex():Void {
		super.vertex();
		vNormal = matrix.normal * normalize(aNormal);
	}

	function fragment():Void {
		oColor = vec4(normalize(vNormal), -vPosition.z);
	}
}

class BlurShader extends BaseShader {
	function fragment():Void {
		final uv = vTexCoord;
		final step = 1.0 / textureSize(material.texture, 0).x;
		var sum = vec3(0);
		var weight = 0.0;
		final r = 1;
		for (i in -r...r + 1) {
			for (j in -r...r + 1) {
				final offset = vec2(i, j) * step;
				final color = texture(material.texture, uv + offset);
				final w = 1.0 / (0.5 + i * i + j * j);
				sum += color.xyz * w;
				weight += w;
			}
		}
		oColor = vec4(sum / weight, 1);
	}
}

class CausticsShader extends BaseShader {
	@uniform var lightCameraY:Float;

	function rand(xyz:Vec3):Float {
		return fract(sin(dot(xyz, vec3(12.9898, 78.233, 45.543))) * 43758.5453);
	}

	function vertex():Void {
		var pos = aPosition.xyz;
		final fr = texture(lightFront, aTexCoord);
		final strength = 0.06;
		var color:Vec3;
		var dirw:Vec3;
		if (fr.w == 0) {
			color = vec3(0.54228, 0.41416, 0.29455) * strength;
			dirw = -mat3(invLightView)[2];
		} else {
			final s = rand(vec3(aPosition.xy, aPosition.z + mod(time, 1.0)));
			color = texture(spectrum, vec2(s, 0.5)).xyz * strength;
			pos.z -= fr.w;
			final bk = texture(lightBack, aTexCoord);
			final nb = -bk.xyz;
			final nf = fr.xyz;
			final n = normalize(mix(nf, nb, BACK_NORMAL_MIX_CAUSTICS));
			final refrIndex = REFRACTION_INDEX_CAUSTICS * (0.75 + 0.5 * s);
			final refrDir = refract(vec3(0, 0, -1), n, refrIndex);
			dirw = mat3(invLightView) * refrDir;
		}
		vColor = vec4(color, 1);
		var posw = (invLightView * vec4(pos, 1)).xyz;
		final t = (groundY - posw.y) / dirw.y;
		posw += t * dirw;
		gl_Position = matrix.projection * (matrix.view * vec4(posw, 1));
		gl_PointSize = 1;
	}

	function fragment():Void {
		oColor = vColor;
	}
}

class MainShader extends BaseShader {
	function raycastGround(pos:Vec3, dir:Vec3):Vec4 {
		final t = (groundY - pos.y) / dir.y;
		if (t > 0) {
			final gpos = pos + t * dir;
			if (abs(gpos.x) < groundSize * 0.5 && abs(gpos.z) < groundSize * 0.5) {
				final checker = mod(floor(gpos.x * 2.0) + floor(gpos.z * 2.0), 2.0);
				final uv = vec2(gpos.x / groundSize + 0.5, 0.5 - gpos.z / groundSize);
				final color = 0.1 + checker * 0.1 + texture(caustics, uv).xyz;
				return vec4(color, t);
			}
		}
		return vec4(EquirectangularTools.sampleTexture(env, dir), 0);
	}

	function fragment():Void {
		final fr = texture(front, vTexCoord);
		if (fr.w > 0) {
			final bk = texture(back, vTexCoord);
			final nf = fr.xyz;
			final nb = -bk.xyz;
			final eyeDir = normalize(vPosition);
			final n = normalize(mix(nf, nb, BACK_NORMAL_MIX));
			final reflected = reflect(eyeDir, nf);
			final refracted = refract(eyeDir, n, REFRACTION_INDEX);
			final fresnel = pow(1.0 + dot(eyeDir, nf), 3.0);
			final invView3 = transpose(mat3(matrix.view));
			final eyeDirInWorld = invView3 * eyeDir;
			final cameraPos = -invView3 * matrix.view[3].xyz;
			final colorBg = raycastGround(cameraPos, eyeDirInWorld);
			if (colorBg.w > 0) {
				final wbgpos = cameraPos + colorBg.w * eyeDirInWorld;
				final vbgpos = (matrix.view * vec4(wbgpos, 1)).xyz;
				if (-vbgpos.z < fr.w) {
					oColor = vec4(colorBg.xyz, 1);
					return;
				}
			}
			final reflectedInWorld = invView3 * reflected;
			final refractedInWorld = invView3 * refracted;
			final specular = pow(max(dot(reflectedInWorld, normalize(vec3(0, 1, 0))), 0.0), 256.0);
			final vpos = eyeDir * fr.w;
			final wpos = invView3 * vpos + cameraPos;
			final colorRefl = raycastGround(wpos, reflectedInWorld).xyz;
			final colorRefr = raycastGround(wpos, refractedInWorld).xyz;
			final color = fresnel * 0.2 + mix(colorRefr, colorRefl, 0.2 + 0.8 * fresnel) + specular * 2;
			oColor = vec4(color, 1);
		} else {
			final eyeDir = normalize(vPosition);
			final invView3 = transpose(mat3(matrix.view));
			final eyeDirInWorld = invView3 * eyeDir;
			final cameraPos = -invView3 * matrix.view[3].xyz;
			final color = raycastGround(cameraPos, eyeDirInWorld).xyz;
			oColor = vec4(color, 1);
		}
	}
}
