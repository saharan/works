private enum Parent {
	Level(level:Level);
	Undetermined(time:Int, pattern:Int);
}

class Level {
	// static inline final FP_POS_X = 1091;
	// static inline final FP_POS_Y = 994;
	// static inline final FP_TIME = 10000;
	// static inline final FP_PATTERN = 308;
	var parent:Parent;

	// position relative to the parent's position
	public var posX:Int;
	public var posY:Int;

	public var time:Int; // from 0 to PERIOD-1

	final patternCache:Map<Int, Int> = [];
	final sampler:Sampler;

	function new(posX:Int, posY:Int, time:Int, parent:Parent, sampler:Sampler) {
		this.posX = posX;
		this.posY = posY;
		this.time = time;
		this.parent = parent;
		this.sampler = sampler;
	}

	public static function generateRandomLevel(sampler:Sampler):Level {
		final index = Std.random(64);
		final loc = sampler.sampleLocation(sampler.frames.location.patterns[index]);
		return new Level(loc.x, loc.y, 0, Undetermined(loc.time, loc.pattern), sampler);
	}

	extern static inline function div(x:Int):Int {
		return x >> 11;
	}

	extern static inline function floor(x:Int):Int {
		return x - mod(x);
	}

	extern static inline function mod(x:Int):Int {
		return x & 2047;
	}

	public function translate(dx:Int, dy:Int):Void {
		translateImpl(this, dx, dy);
	}

	static function translateImpl(level:Level, dx:Int, dy:Int):Void {
		final levels = [];
		final deltas = [];
		assert(dx != 0 || dy != 0);
		var depth = 0;
		while (true) {
			levels.push(level);
			final px = level.posX;
			final py = level.posY;
			level.posX += dx;
			level.posY += dy;
			dx = div(level.posX);
			dy = div(level.posY);
			level.posX = mod(level.posX);
			level.posY = mod(level.posY);
			deltas.push(level.posY - py);
			deltas.push(level.posX - px);
			depth++;
			if (dx == 0 && dy == 0)
				break;
			level = level.getParent();
		}
		var dxTotal = 0;
		var dyTotal = 0;
		final newCache = [];
		var cut = false;
		while (deltas.length > 0) {
			depth--;
			final level = levels.pop();
			final dx = deltas.pop();
			final dy = deltas.pop();
			if (!cut) {
				dxTotal -= dx;
				dyTotal -= dy;
				if (depth < 1000) { // keep cache of only nearest 1000 levls
					for (key => value in level.patternCache) {
						final x = (key & 0xffff) << 16 >> 16;
						final y = key >> 16;
						final newX = x + dxTotal;
						final newY = y + dyTotal;
						if (newX >= -2048 && newX < 2048 && newY >= -2048 && newY < 2048) {
							final newKey = (newX & 0xffff) | (newY & 0xffff) << 16;
							newCache.push(value);
							newCache.push(newKey);
						}
					}
				}
			}
			level.patternCache.clear();
			if (!cut) {
				while (newCache.length > 0) {
					final key = newCache.pop();
					final value = newCache.pop();
					level.patternCache[key] = value;
				}
				dxTotal *= 2048;
				dyTotal *= 2048;
				if (abs(dxTotal) + abs(dyTotal) > 10000)
					cut = true;
			}
		}
	}

	public function getParent():Level {
		return switch parent {
			case Level(level):
				level;
			case Undetermined(time, pattern):
				final loc = sampler.sampleLocation(pattern);
				final level = new Level(loc.x, loc.y, time, Undetermined(loc.time, loc.pattern), sampler);
				parent = Level(level);
				return level;
		}
	}

	public function makeSubLevel(x:Int, y:Int, time:Int):Level {
		return new Level(x, y, time, Level(this), sampler);
	}

	function getParentTime():Int {
		return switch parent {
			case Level(level):
				level.time;
			case Undetermined(time, _):
				time;
		}
	}

	// begin before recursion elimination

	function getParentPattern(px:Int, py:Int):Int {
		return switch parent {
			case Undetermined(_, pattern) if (px == 0 && py == 0):
				pattern;
			case _:
				getParent().getPatternOfCell(px, py);
		}
	}

	function getBitOfCell(relX:Int, relY:Int, prev:Bool):Int {
		final x = posX + relX;
		final y = posY + relY;
		final px = div(x);
		final py = div(y);
		final p = getParentPattern(px, py);
		return sampler.sampleBit(getParentTime() - (prev ? 1 : 0), mod(x), mod(y), p);
	}

	public function getPatternOfCell(relX:Int, relY:Int):Int {
		return getPatternOfCellImpl(this, relX, relY, sampler);

		// final newImplBit = getPatternOfCellImpl(this, relX, relY, sampler);

		// final key = (relX & 0xffff) | (relY & 0xffff) << 16;
		// if (patternCache.exists(key))
		// 	return patternCache[key];
		// var bit = getBitOfCell(relX - 1, relY - 1, false);
		// bit |= getBitOfCell(relX, relY - 1, false) << 1;
		// bit |= getBitOfCell(relX + 1, relY - 1, false) << 2;
		// bit |= getBitOfCell(relX - 1, relY, false) << 3;
		// bit |= getBitOfCell(relX, relY, false) << 4;
		// bit |= getBitOfCell(relX + 1, relY, false) << 5;
		// bit |= getBitOfCell(relX - 1, relY + 1, false) << 6;
		// bit |= getBitOfCell(relX, relY + 1, false) << 7;
		// bit |= getBitOfCell(relX + 1, relY + 1, false) << 8;
		// bit |= getBitOfCell(relX, relY, true) << 9;
		// bit ^= (bit >> 4 & 1) << 9;
		// patternCache[key] = bit;

		// assert(bit == newImplBit);

		// return bit;
	}

	// end before recursion elimination
	static inline final GET_PATTERN = 0;
	static inline final GET_PATTERN1 = 1;
	static inline final GET_PATTERN2 = 2;
	static inline final GET_PATTERN3 = 3;
	static inline final GET_PATTERN4 = 4;
	static inline final GET_PATTERN5 = 5;
	static inline final GET_PATTERN6 = 6;
	static inline final GET_PATTERN7 = 7;
	static inline final GET_PATTERN8 = 8;
	static inline final GET_PATTERN9 = 9;
	static inline final GET_PATTERN10 = 10;
	static inline final GET_BIT = 11;
	static inline final GET_BIT1 = 12;

	static function getPatternOfCellImpl(level:Level, relX:Int, relY:Int, sampler:Sampler):Int {
		final stackI = [];
		final stackL = [];
		final diffX = [0, 1, -1, 0, 1, -1, 0, 1, 0];
		final diffY = [-1, -1, 0, 0, 0, 1, 1, 1, 0];
		stackL.push(level);
		stackI.push(relY);
		stackI.push(relX);
		stackI.push(GET_PATTERN);
		var ret = -1;
		var count = 0;
		// trace("ground");

		while (stackL.length > 0) {
			count++;
			final level = stackL.pop();
			// trace("args[0]: " + args[0] + " (ret = " + ret + ")");
			switch stackI.pop() {
				case GET_PATTERN:
					final relX = stackI.pop();
					final relY = stackI.pop();
					final key = (relX & 0xffff) | (relY & 0xffff) << 16;
					if (level.patternCache.exists(key)) {
						ret = level.patternCache[key];
					} else {
						stackL.push(level);
						stackI.push(0);
						stackI.push(relY);
						stackI.push(relX);
						stackI.push(GET_PATTERN1);
						stackL.push(level);
						stackI.push(0);
						stackI.push(relY - 1);
						stackI.push(relX - 1);
						stackI.push(GET_BIT);
					}
				case _ - GET_PATTERN1 => step if (step >= 0 && step < 9):
					assert(ret != -1);
					final relX = stackI.pop();
					final relY = stackI.pop();
					final bit = stackI.pop() | ret << step;
					stackL.push(level);
					stackI.push(bit);
					stackI.push(relY);
					stackI.push(relX);
					stackI.push(GET_PATTERN2 + step);
					stackL.push(level);
					stackI.push(step == 8 ? 1 : 0);
					stackI.push(relY + diffY[step]);
					stackI.push(relX + diffX[step]);
					stackI.push(GET_BIT);
				case GET_PATTERN10:
					assert(ret != -1);
					final relX = stackI.pop();
					final relY = stackI.pop();
					final key = (relX & 0xffff) | (relY & 0xffff) << 16;
					var bit = stackI.pop() | ret << 9;
					bit ^= (bit >> 4 & 1) << 9;
					level.patternCache[key] = bit;
					ret = bit;
				case GET_BIT:
					final relX = stackI.pop();
					final relY = stackI.pop();
					final prev = stackI.pop();
					final x = level.posX + relX;
					final y = level.posY + relY;
					final px = div(x);
					final py = div(y);
					switch level.parent {
						case Undetermined(_, pattern) if (px == 0 && py == 0):
							ret = sampler.sampleBit(level.getParentTime() - prev, mod(x), mod(y), pattern);
						case _:
							stackL.push(level);
							stackI.push(prev);
							stackI.push(mod(y));
							stackI.push(mod(x));
							stackI.push(GET_BIT1);
							stackL.push(level.getParent());
							stackI.push(py);
							stackI.push(px);
							stackI.push(GET_PATTERN);
					}
				case GET_BIT1:
					assert(ret != -1);
					final modX = stackI.pop();
					final modY = stackI.pop();
					final prev = stackI.pop();
					ret = sampler.sampleBit(level.getParentTime() - prev, modX, modY, ret);
			}
		}
		// trace("length: " + count);
		return ret;
	}

	public function forward(delta:Int):Bool {
		assert(delta != 0);
		patternCache.clear();
		time += delta;
		final pt = Math.floor(time / Main.PERIOD);
		return if (pt != 0) {
			time -= pt * Main.PERIOD;
			getParent().forward(pt);
			true;
		} else {
			false;
		}
	}

	public function toString(full:Bool = false):String {
		if (full) {
			var res = "";
			var l = this;
			while (l != null) {
				res = " -> (" + l.posX + ", " + l.posY + ", " + l.time + ")" + res;
				l = switch l.parent {
					case Level(level):
						level;
					case _:
						null;
				}
			}
			return "(?, ?, ?)" + res;
		} else {
			var res = "";
			var l = this;
			var count = 0;
			var omitted = 0;
			while (l != null) {
				if (++count < 5) {
					res = " -> (" + l.posX + ", " + l.posY + ", " + l.time + ")" + res;
				} else {
					omitted++;
				}
				l = switch l.parent {
					case Level(level):
						level;
					case _:
						null;
				}
			}
			return "(?, ?, ?)" + (omitted > 0 ? " -> (" + omitted + " more level" + (omitted > 1 ? "s" : "") + ")" : "") + res;
		}
	}
}
