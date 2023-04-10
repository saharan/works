class Sampler {
	public final graph:Graph;
	public final frames:Frames;

	public function new(graph:Graph, frames:Frames) {
		this.graph = graph;
		this.frames = frames;
	}

	public function sampleLocation(pattern:Int):{
		x:Int,
		y:Int,
		time:Int,
		pattern:Int
	} {
		final loc = frames.location;
		final index = loc.indices[pattern];
		assert(index != -1);
		final index2 = Std.random(64);
		final posTime = loc.posTimes[index][index2];
		final parentPattern = loc.patterns[index2];
		assert(pattern == samplePattern(posTime[2], posTime[0], posTime[1],
			[null, null, null, null, parentPattern, null, null, null, null]));
		return {
			x: posTime[0],
			y: posTime[1],
			time: posTime[2],
			pattern: parentPattern
		}
	}

	extern public static inline function fabricatePrevPattern(pattern:Int):Int {
		final now = pattern >> 4 & 1;
		final prev = now ^ (pattern >> 9 & 1);
		// choose a pattern that transits from prev to now
		// 1 -> 0: 16
		// 1 -> 1: 23
		// 0 -> 0: 0
		// 0 -> 1: 7
		return (7 & -now) | (16 & -prev);
	}

	public function samplePattern(time:Int, x:Int, y:Int, patterns:Array<Int>):Int {
		final centerPrev = time > 0 ? sampleBit(time - 1, x, y, patterns[4]) : sampleBit(Main.PERIOD - 1, x, y,
			fabricatePrevPattern(patterns[4]));
		var bit = centerPrev;
		for (dy in -1...2) {
			for (dx in -1...2) {
				final cx = x + dx;
				final cy = y + dy;
				final p = patterns[((cy >> 11) + 1) * 3 + ((cx >> 11) + 1)];
				bit |= sampleBit(time, cx, cy, p) << ((dy + 1) * 3 + (dx + 1));
			}
		}
		bit ^= (bit >> 4 & 1) << 9;
		return bit;
	}

	public function sampleBit(time:Int, x:Int, y:Int, pattern:Int):Int {
		if (time == -1) {
			time += Main.PERIOD;
			pattern = fabricatePrevPattern(pattern);
		}
		assert(time >= 0 && time < Main.PERIOD);
		assert(x >= 0 && x < 2048);
		assert(y >= 0 && y < 2048);
		final tx = x >> 9;
		final ty = y >> 9;
		final nodeIndex = frames.getTile(time, pattern, tx, ty);
		return graph.getBit(9, nodeIndex, x & 511, y & 511);
	}

	public function getTiles(time:Int, pattern:Int):Array<Int> {
		if (time == -1) {
			time += Main.PERIOD;
			pattern = fabricatePrevPattern(pattern);
		}
		return frames.getTiles(time, pattern);
	}

	public function getTile(time:Int, pattern:Int, tileX:Int, tileY:Int):Int {
		if (time == -1) {
			time += Main.PERIOD;
			pattern = fabricatePrevPattern(pattern);
		}
		return frames.getTile(time, pattern, tileX, tileY);
	}
}
