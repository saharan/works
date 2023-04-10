class Decoder {
	static inline final PERIOD = 35328;

	public final graph = new Graph();
	public final frames = new Frames();

	public function new() {
	}

	public function decodeGraph(pixels:Array<Int>):Void {
		var len = pixels.length;
		while (pixels[len - 1] & 0xffffff == 0)
			len--;
		final ints = [];
		for (i in 0...len) {
			final num = pixels[i] & 0x7ffff;
			final count = ((pixels[i] >> 19) & 31) + 1;
			for (i in 0...count) {
				ints.push(num);
			}
		}
		assert(ints.length % 4 == 0);
		final numNodes = ints.length >> 2;
		var level = 3;
		for (i in 0...numNodes) {
			if (i > 0 && ints[i - 1] != 0 && ints[i] == 0)
				level++;
			graph.add(level, [ints[i], ints[i + numNodes], ints[i + numNodes * 2], ints[i + numNodes * 3]]);
		}
		for (i in 3...10) {
			trace("nodes of level " + i + ": " + graph.numNodesOfLevel(i));
		}
		trace("max population: " + graph.maxPopulation);
	}

	public function decodeAnim(pixels:Array<Int>):Void {
		var p = 0;
		inline function next():Int {
			return pixels[p] & 0xffffff;
		}
		inline function read():Int {
			return pixels[p++] & 0xffffff;
		}

		final numPatterns = read();
		trace("num patterns: " + numPatterns);
		for (i in 0...numPatterns) {
			final pattern = [];
			var sum = 0;
			while (sum < 1024) {
				if (next() == 0) {
					pattern.push(read());
					sum++;
				} else {
					final pos = read();
					final len = read();
					pattern.push(pos);
					pattern.push(len);
					sum += len;
				}
			}
			frames.addPattern(pattern);
			assert(sum == 1024);
		}
		final patternIndices = [];
		for (i in 0...PERIOD) {
			patternIndices.push([]);
			for (j in 0...16) {
				patternIndices[i].push(read());
			}
		}
		for (i in 0...PERIOD) {
			frames.addFrame();
			for (j in 0...16) {
				var indices = [];
				final patternIndex = patternIndices[i][j];
				final numPlaceholders = frames.patterns[patternIndex].numPlaceholders;
				for (k in 0...numPlaceholders) {
					indices.push(read());
				}
				frames.addTileToLastFrame(patternIndex, indices);
			}
		}
	}

	public function decodeLocation(pixels:Array<Int>):Void {
		assert(pixels.length >= 8256);
		var p = 0;
		for (i in 0...64) {
			frames.addPatternForLocation(pixels[p++] & 0xffffff);
		}
		for (i in 0...64) {
			for (j in 0...64) {
				final xy = pixels[p++] & 0xffffff;
				final time = pixels[p++] & 0xffffff;
				frames.addLocation(i, xy & 0xfff, xy >> 12, time);
			}
		}
	}
}
