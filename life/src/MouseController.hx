import pot.input.Mouse;
import muun.la.Vec2;
import pot.input.Input;

class MouseController {
	final univ:Universe;
	final input:Input;
	final mouse:Mouse;
	var dragging:Bool = false;

	var scaleVelocity:Float = 0;

	final velocity:Vec2 = Vec2.zero;
	final left:Vec2 = Vec2.zero;
	final anchor:Vec2 = Vec2.zero;

	var autoScrollSign:Int = 0;
	var autoScrollAccum:Float = 0;

	public function new(univ:Universe, input:Input) {
		this.univ = univ;
		this.input = input;
		mouse = input.mouse;
	}

	public function update(width:Float, height:Float, control:Bool, autoScaleSpeed:Float):Void {
		final mpos = Vec2.of(mouse.x, mouse.y);
		final center = Vec2.of(width, height) * 0.5;
		if (mouse.dleft == 1 && control) {
			velocity << Vec2.zero;
			left << Vec2.zero;
			dragging = true;
		} else if (mouse.dleft == -1 && control) {
			dragging = false;
		} else if (mouse.left && control) {
			final delta = Vec2.of(mouse.dx, mouse.dy);
			left += delta;
			velocity << left * 0.5;
			left *= 0.5;
		} else {
			velocity *= 0.95;
		}
		autoScrollAccum *= 0.9;
		autoScrollAccum += mouse.wheelY;

		if (autoScrollSign == 0) {
			anchor << mpos;
			if (abs(autoScrollAccum) > 200) {
				autoScrollSign = sign(autoScrollAccum);
				autoScrollAccum = 0;
			}
		} else {
			anchor += (center - anchor) * 0.1;
			if (sign(autoScrollAccum) != autoScrollSign)
				autoScrollSign = 0;
		}

		// scaleVelocity += Math.pow(1.2, mouse.wheelY / 100.0) - 1;
		scaleVelocity = Math.pow(1.2, mouse.wheelY / 100.0 + Math.log(scaleVelocity + 1) / Math.log(1.2)) - 1;
		if (scaleVelocity > 10)
			scaleVelocity = 10;

		final scaleVelTarget = autoScrollSign * autoScaleSpeed;
		scaleVelocity += (scaleVelTarget - scaleVelocity) * 0.3;
		final scaleDiff = (anchor - center) * scaleVelocity;
		final translate = velocity + scaleDiff;

		univ.translateCamera(-translate.x / width, -translate.y / height);
		univ.scaleCamera(1 + scaleVelocity);
		univ.normalizeZoom(width);
	}
}
