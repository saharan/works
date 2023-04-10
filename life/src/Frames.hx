typedef Pattern = {
	pattern:Array<Int>,
	numPlaceholders:Int
}

typedef Tile = {
	patternIndex:Int,
	nodeIndices:Array<Int>
}

typedef Location = {
	patterns:Array<Int>,
	indices:Array<Int>,
	posTimes:Array<Array<Array<Int>>>
}

class Frames {
	public final patterns:Array<Pattern> = [];
	public final frames:Array<Array<Tile>> = [];
	public final location:Location = {
		patterns: [],
		indices: [for (i in 0...1024) -1],
		posTimes: [for (i in 0...64) []]
	};

	public function new() {
	}

	public function addPatternForLocation(pattern:Int):Void {
		location.indices[pattern] = location.patterns.push(pattern) - 1;
	}

	public function addLocation(patternIndex:Int, x:Int, y:Int, time:Int):Void {
		location.posTimes[patternIndex].push([x, y, time]);
	}

	public function addPattern(compressedPattern:Array<Int>):Void {
		patterns.push({
			pattern: decompressPattern(compressedPattern),
			numPlaceholders: compressedPattern.filter(i -> i == 0).length
		});
	}

	public function addFrame():Void {
		frames.push([]);
	}

	public function addTileToLastFrame(patternIndex:Int, nodeIndices:Array<Int>):Void {
		assert(frames.length > 0 && frames[frames.length - 1].length < 16);
		frames[frames.length - 1].push({
			patternIndex: patternIndex,
			nodeIndices: nodeIndices
		});
	}

	function decompressPattern(compressedPattern:Array<Int>):Array<Int> {
		final p = compressedPattern;
		final res = [];
		var insertionCount = 0;
		var i = 0;
		while (res.length < 1024) {
			if (p[i] == 0) {
				res.push(insertionCount++);
				i++;
			} else {
				final pos = p[i++] - 1;
				final len = p[i++];
				for (i in 0...len) {
					res.push(res[pos + i]);
				}
			}
		}
		assert(res.length == 1024);
		return res;
	}

	public function restoreFrame(time:Int):Array<Array<Int>> {
		final frame = frames[time];
		final res = [];
		for (tile in frame) {
			final pattern = patterns[tile.patternIndex];
			final p = pattern.pattern;
			final nodeIndices = tile.nodeIndices;
			assert(nodeIndices.length == pattern.numPlaceholders);
			final indices = [];
			for (i in 0...1024) {
				indices.push(nodeIndices[p[i]]);
			}
			res.push(indices);
		}
		return res;
	}

	public function getTiles(time:Int, pattern:Int):Array<Int> {
		final frame = frames[time];
		final res = [];
		for (tile in frame) {
			final p = patterns[tile.patternIndex].pattern[pattern];
			res.push(tile.nodeIndices[p]);
		}
		return res;
	}

	public function getTile(time:Int, pattern:Int, tileX:Int, tileY:Int):Int {
		final tile = frames[time][tileY << 2 | tileX];
		final p = patterns[tile.patternIndex].pattern[pattern];
		return tile.nodeIndices[p];
	}
}
