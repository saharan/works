import muun.la.Vec2;
import phys.Box;
import phys.Body;
import phys.World;

class Layer {
	public static inline final NUM_FRAMES:Int = 300;
	public static inline final WIDTH:Int = 246;
	public static inline final HEIGHT:Int = 50;
	public static inline final DEPTH:Int = 250;
	public static inline final PREPARATION_MULT:Int = 6;
	public static inline final SUBSTEPS:Int = 2;

	final chars:String = "0123456789:";
	final charData:Array<Int> = [31599, 4681, 29671, 29647, 23497, 31183, 31215, 29257, 31727, 31695, 1040];

	public final w:World = new World();
	public final time:Float;
	public final hoursString:String;
	public final minutesString:String;
	public final secondsString:String;

	var preparedFrames:Int = 0;
	var currentFrame:Int = 0;

	public function new(time:Float) {
		this.time = time;
		inline function format(num:Int):String {
			return num < 10 ? "0" + num : Std.string(num);
		}
		final date = Date.fromTime(time);
		hoursString = format(date.getHours());
		minutesString = format(date.getMinutes());
		secondsString = format(date.getSeconds());
		initWorld();
	}

	function initWorld():Void {
		final width = WIDTH;
		final height = HEIGHT;
		w.bs.push(new Body(Vec2.of(width * 0.5, -200)).setShape(new Box(200, 200), 0));
		w.bs.push(new Body(Vec2.of(-200, height * 0.5)).setShape(new Box(200, 200), 0));
		w.bs.push(new Body(Vec2.of(width + 200, height * 0.5)).setShape(new Box(200, 200), 0));

		var x = 30;
		var y = secondsString == "00" ? 40 : secondsString.charAt(1) == "0" ? 20 : 0;
		final largeSize = 8;
		final smallSize = 5;
		placeChar(hoursString.charAt(0), x, y, largeSize);
		x += largeSize * 4;
		placeChar(hoursString.charAt(1), x, y, largeSize);
		x += largeSize * 3;
		placeChar(":", x, y, largeSize);
		x += largeSize * 3;
		placeChar(minutesString.charAt(0), x, y, largeSize);
		x += largeSize * 4;
		placeChar(minutesString.charAt(1), x, y, largeSize);
		x += largeSize * 3;
		placeChar(":", x, y, smallSize);
		x += smallSize * 3;
		placeChar(secondsString.charAt(0), x, y, smallSize);
		x += smallSize * 4;
		placeChar(secondsString.charAt(1), x, y, smallSize);
		x += smallSize * 3;
		x += 30;

		w.startRec();
	}

	public function prepareNextFrame():Void {
		if (preparedFrames >= NUM_FRAMES)
			return;
		for (i in 0...PREPARATION_MULT) {
			preparedFrames++;
			w.step(true);
		}
		if (preparedFrames >= NUM_FRAMES) {
			w.stopRec();
		}
	}

	public function ready():Bool {
		return preparedFrames >= NUM_FRAMES;
	}

	public function nextFrame():Void {
		if (currentFrame >= NUM_FRAMES) {
			for (i in 0...SUBSTEPS)
				w.step();
		} else {
			for (i in 0...SUBSTEPS)
				w.playRec(true);
		}
		currentFrame += SUBSTEPS;
	}

	public function position():Float {
		return currentFrame / NUM_FRAMES;
	}

	function placeChar(char:String, leftX:Float, bottomY:Float, size:Float):Void {
		inline function add(x:Int, y:Int, w:Int, h:Int):Void {
			final bl = leftX + x * size;
			final bb = bottomY + y * size;
			final bw = size * w * 0.5;
			final bh = size * h * 0.5;
			final b = new Body(Vec2.of(bl + bw, bb + bh)).setShape(new Box(bw, bh));
			b.v.x = Math.random() * 0.01 - 0.005;
			b.v.y = Math.random() * 0.01 - 0.005;
			this.w.bs.push(b);
		}

		final val = charData[chars.indexOf(char)];
		for (i in 0...5) {
			final row = val >> (i * 3) & 7;
			switch row {
				case 0: // 000
				case 1: // 001
					add(2, i, 1, 1);
				case 2: // 010
					add(1, i, 1, 1);
				case 3: // 011
					add(1, i, 2, 1);
				case 4: // 100
					add(0, i, 1, 1);
				case 5: // 101
					add(0, i, 1, 1);
					add(2, i, 1, 1);
				case 6: // 110
					add(0, i, 2, 1);
				case 7: // 111
					add(0, i, 3, 1);
			}
		}
	}
}
