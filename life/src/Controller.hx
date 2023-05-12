import pot.input.Touches;
import pot.input.Mouse;
import muun.la.Vec2;
import pot.input.Input;

class Controller {
	public static final AUTO_SCALE_SPEED_BASE:Float = 0.02;

	public final univ:Universe;
	public final input:Input;

	final mc:MouseController;
	final tc:TouchController;

	var barX:Float = 0;
	var barY:Float = 0;
	var barW:Float = 0;
	var barH:Float = 0;
	var barPad:Float = 0;


	final mouse:Mouse;
	final touches:Touches;

	public var barFocus(default, null):Bool = false;
	public var barT(default, null):Float = 0.3;

	var barT2:Float = 0.3;

	public function new(univ:Universe, input:Input) {
		this.univ = univ;
		this.input = input;
		mouse = input.mouse;
		touches = input.touches;
		mc = new MouseController(univ, input);
		tc = new TouchController(univ, input);
	}

	public function setBar(x:Float, y:Float, w:Float, h:Float, pad:Float):Void {
		barX = x;
		barY = y;
		barW = w;
		barH = h;
		barPad = pad;
	}

	public function update(width:Float, height:Float, heat:Float):Void {
		final mpos = Vec2.zero;
		var press = false;
		var barTest = false;
		var updateFocus = false;
		if (mouse.hasInput) {
			barTest = true;
			mpos <<= Vec2.of(mouse.x, mouse.y);
			press = mouse.left;
			updateFocus = !press;
		} else {
			if (touches.length == 0 || touches[0].dtouching == -1)
				barFocus = false;
			barTest = barFocus;
			if (touches.length > 0) {
				barTest = true;
				press = touches[0].touching;
				updateFocus = touches[0].dtouching == 1;
				mpos <<= Vec2.of(touches[0].x, touches[0].y);
			}
		}
		if (barTest) {
			final barHit = mpos.x >= barX && mpos.x < barX + barW + barPad * 2 && mpos.y >= barY && mpos.y < barY + barH + barPad * 2;
			if (updateFocus)
				barFocus = barHit;
			if (press && barFocus) {
				barT2 = clamp((mpos.x - (barX + barPad)) / barW, 0, 1);
				if (barT2 >= 0.275 && barT2 <= 0.325)
					barT2 = 0.3;
			}
		}
		barT += (barT2 - barT) * 0.5;
		final autoScaleSpeed = AUTO_SCALE_SPEED_BASE * Math.pow(2, heat * 4);
		if (mouse.hasInput) {
			mc.update(width, height, !barFocus, autoScaleSpeed);
		} else {
			tc.update(width, height, !barFocus, autoScaleSpeed);
		}
	}
}
