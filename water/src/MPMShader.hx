import hgsl.Global.*;
import pot.graphics.gl.shader.DefaultShader;

class MPMShader extends DefaultShader {
	function vertex():Void {
		gl_Position = matrix.transform * aPosition;
		final t = aColor.z;
		final c1 = vec3(0.1, 0.2, 0.6);
		final c2 = vec3(0.5, 0.9, 1.0);
		vColor = vec4(mix(c1, c2, t), 1);
		vTexCoord = aTexCoord;
	}

	function fragment():Void {
		final color = vColor.xyz;
		final uv = vTexCoord;
		final weight = 1 - length(2 * uv - 1);
		final alpha = clamp(10 * weight, 0, 1);
		if (alpha == 0)
			discard();
		oColor = vec4(color * alpha, 1);
		gl_FragDepth = 0.5 - weight * 0.1;
	}
}
