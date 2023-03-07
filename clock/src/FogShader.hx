import pot.graphics.gl.shader.DefaultShader;
import hgsl.Types;
import hgsl.Global.*;

class FogShader extends DefaultShader {
	@uniform var bgColor:Vec3;

	function fragment():Void {
		super.fragment();
		oColor = vec4(mix(bgColor, oColor.xyz, vColor.w), 1);
	}
}
