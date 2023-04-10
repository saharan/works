import pot.input.Touches;
import pot.input.Touch;
import muun.la.Vec2;
import pot.input.Input;

class TouchController {
	final univ:Universe;
	final input:Input;
	final touches:Touches;
	var id1:Int = -1;
	var id2:Int = -1;

	var autoScrollSign:Int = 0;
	var scaleVelocity:Float = 0;

	final velocity:Vec2 = Vec2.zero;
	final left:Vec2 = Vec2.zero;
	final anchor:Vec2 = Vec2.zero;

	public function new(univ:Universe, input:Input) {
		this.univ = univ;
		this.input = input;
		touches = input.touches;
	}

	inline function find(id:Int):Touch {
		var res = null;
		for (touch in touches) {
			if (touch.id == id) {
				res = touch;
				break;
			}
		}
		return res;
	}

	public function update(width:Float, height:Float, control:Bool, autoScaleSpeed:Float):Void {
		final center = Vec2.of(width, height) * 0.5;

		if (control) {
			for (touch in touches) {
				if (touch.dtouching == 1) {
					if (id1 == -1) {
						id1 = touch.id;
					} else if (id2 == -1) {
						id2 = touch.id;
					}
				}
			}

			if (id1 != -1 && find(id1).dtouching == -1) {
				id1 = -1;
			}
			if (id2 != -1 && find(id2).dtouching == -1) {
				id2 = -1;
			}
			if (id1 == -1) {
				id1 = id2;
				id2 = -1;
			}
		}

		final touch1 = find(id1);
		final touch2 = find(id2);
		final pos1 = Vec2.zero;
		final pos2 = Vec2.zero;

		if (id1 != -1) {
			pos1 << Vec2.of(touch1.x, touch1.y);
		}
		if (id2 != -1) {
			pos2 << Vec2.of(touch2.x, touch2.y);
		}

		var targetScaleVelocity = -1.0;
		if (id1 != -1 && id2 == -1) { // sliding only
			final delta = Vec2.of(touch1.dx, touch1.dy);
			left += delta;
			if (touch1.dtouching == 1)
				left << Vec2.zero;
			velocity << left * 0.5;
			left *= 0.5;
			if (autoScrollSign == 0)
				anchor += (pos1 - anchor) * 0.1;
			else
				anchor += (center - anchor) * 0.5;
		} else if (id1 != -1 && id2 != -1) { // sliding + scaling
			anchor += ((pos1 + pos2) * 0.5 - anchor) * 0.1;
			final delta1 = Vec2.of(touch1.dx, touch1.dy);
			final delta2 = Vec2.of(touch2.dx, touch2.dy);
			final delta = (delta1 + delta2) * 0.5;
			left += delta;
			velocity << left * 0.5;
			left *= 0.5;
			final d1 = ((pos2 + delta2) - (pos1 + delta1)).length;
			final d2 = (pos2 - pos1).length;
			targetScaleVelocity = d2 / d1 - 1;
			autoScrollSign = 0;
		} else if (id1 == -1 && id2 == -1) {
			anchor += (center - anchor) * 0.5;
			velocity *= 0.95;
		}
		if (targetScaleVelocity == -1) {
			scaleVelocity += (autoScrollSign * autoScaleSpeed - scaleVelocity) * 0.1;
		} else {
			if (abs(targetScaleVelocity) > 0.1)
				autoScrollSign = sign(targetScaleVelocity);
			scaleVelocity = targetScaleVelocity;
		}

		final scaleDiff = (anchor - center) * scaleVelocity;
		final translate = velocity + scaleDiff;
		univ.translateCamera(-translate.x / width, -translate.y / height);
		univ.scaleCamera(1 + scaleVelocity);
		univ.normalizeZoom(width);
	}
}
