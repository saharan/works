package generator;

import java.awt.image.BufferedImage;
import java.awt.image.DataBufferInt;
import java.javax.imageio.ImageIO;
import java.util.HashSet;
import java.util.Set;
import sys.io.File;

using Lambda;

class TokenReader {
	final tokens:Array<String>;
	var i:Int;

	public function new(tokens:Array<String>) {
		this.tokens = tokens;
		i = 0;
	}

	public function end():Bool {
		return i == tokens.length;
	}

	public function read():String {
		return tokens[i++];
	}

	public function next():String {
		return tokens[i];
	}
}

class Compress {
	static inline final PERIOD = 35328;

	// compress raw animation outputs
	static function compressRLE():Void {
		final anims = [for (i in 0...PERIOD) [for (j in 0...16) new AnimBlock()]];
		for (f in 0...1024) {
			final lines = File.getContent("anims/" + f + ".txt").split("\n");
			for (i in 0...16) {
				final ids = lines[i].split(" ").map(Std.parseInt);
				trace(ids.length);
				for (t in 0...PERIOD) {
					anims[t][i].add(ids[t]);
				}
			}
			trace("progress: " + f + "/1024");
			trace("sample: " + anims[10000][2].toString());
		}
		File.saveContent("anims.txt", anims.map(anim -> anim.map(block -> block.toString()).join("\n")).join("\n\n"));
	}

	// remap node ids so that ids in each level start from 0
	static function compressIDs():Void {
		inline function comp(a:Int, b:Int):Int {
			return a < b ? -1 : a > b ? 1 : 0;
		}
		trace("loading nodes...");
		final levelOffsets = [0];
		final nodes = File.getContent("graph.txt").split("\n").map(line -> {
			final ints = line.split(" ").map(Std.parseInt);
			{
				origId: ints[0],
				level: ints[1],
				pop: ints[2],
				children: ints[1] == 0 ? [] : [ints[3], ints[4], ints[5], ints[6]],
				mappedChildren: ints[1] == 0 ? [] : [ints[3], ints[4], ints[5], ints[6]]
			}
		});
		trace("nodes loaded.");
		nodes.sort((a, b) -> comp(a.level, b.level) * 2 + comp(a.pop, b.pop));
		final nodeCounts = [for (i in 0...10) 0];
		for (node in nodes) {
			if (levelOffsets.length == node.level + 1) {
				levelOffsets.push(levelOffsets[levelOffsets.length - 1]);
			}
			levelOffsets[node.level + 1]++;
			nodeCounts[node.level]++;
		}
		trace("node counts: " + nodeCounts);
		trace("level offsets: " + levelOffsets);

		final map:Map<Int, Int> = [];
		for (iter in 0...10) {
			trace("generating map... " + (iter + 1) + "/10");
			for (i => node in nodes) {
				if (node.level > 0)
					node.mappedChildren = [map[node.children[0]], map[node.children[1]], map[node.children[2]], map[node.children[3]]];
				map.set(node.origId, i - levelOffsets[node.level]);
			}
			nodes.sort((a, b) -> {
				final lc = comp(a.level, b.level);
				if (lc != 0)
					return lc;
				if (a.level == 0)
					return comp(a.pop, b.pop);
				return comp(a.mappedChildren[0], b.mappedChildren[0]) * 8 + comp(a.mappedChildren[1], b.mappedChildren[1]) * 4 +
					comp(a.mappedChildren[2], b.mappedChildren[2]) * 2 + comp(a.mappedChildren[3], b.mappedChildren[3]);
			});
		}
		{
			final fo = File.write("graph_mapped.txt", false);
			for (node in nodes) {
				if (node.level > 0) {
					final cs = [map[node.children[0]], map[node.children[1]], map[node.children[2]], map[node.children[3]]];
					fo.writeString(cs.join(" ") + "\n");
				}
			}
			fo.close();
		}
		{
			final lines = File.getContent("anims.txt").split("\n");
			final fo = File.write("anims_mapped.txt", false);
			for (line in lines) {
				final line2 = line.split(" ").map(s -> s.charAt(0) == "i" ? "i" + map[Std.parseInt(s.substr(1))] : s).join(" ");
				fo.writeString(line2 + "\n");
			}
			fo.close();
		}
		// {
		// 	final fo = File.write("map.txt", false);
		// 	for (i => node in nodes) {
		// 		fo.writeString(node.origId + " " + map[node.origId] + "\n");
		// 	}
		// 	fo.close();
		// }
	}

	// generate a png file that contains the data of all nodes
	static function compressGraph():Void {
		trace("generating graph.png...");
		final lines = File.getContent("graph_compressed.txt").split("\n");
		final nums = [];
		for (l in lines) {
			final ints = l.split(" ").map(Std.parseInt);
			if (l == "") {
				continue;
			}
			if (ints.length != 4)
				throw "nope";
			nums.push(ints[0]);
			nums.push(ints[1]);
			nums.push(ints[2]);
			nums.push(ints[3]);
		}
		trace(nums.length);
		final numNodes = nums.length >> 2;

		final nums2 = [];
		nums2.resize(numNodes * 4);
		for (i => n in nums) {
			final nodeIndex = i >> 2;
			final subIndex = i & 3;
			nums2[subIndex * numNodes + nodeIndex] = n;
		}
		final nums3 = [];
		for (n in nums2) {
			final last = nums3.length == 0 ? null : nums3[nums3.length - 1];
			if (last != null && last[0] == n && last[1] < 31)
				last[1]++;
			else
				nums3.push([n, 0]);
		}
		trace(nums3.length);
		final w = 1645;
		final h = 1645;
		if (nums3.length > w * h)
			throw "nope";
		final bi = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
		final pixs = cast(bi.getRaster().getDataBuffer(), DataBufferInt).getData();
		for (i => n in nums3) {
			if (n[0] >= 1 << 19 || n[1] >= 32)
				throw "nope";
			pixs[i] = n[0] | n[1] << 19;
		}
		ImageIO.write(bi, "png", new java.io.File("graph.png"));
	}

	extern static inline function min(a:Int, b:Int):Int {
		return a < b ? a : b;
	}

	static function parseTokens(tr:TokenReader):Array<Int> {
		var res = [];
		while (!tr.end()) {
			res = res.concat(parseToken(tr));
		}
		return res;
	}

	static function parseToken(tr:TokenReader):Array<Int> {
		if (tr.end())
			return [];
		return switch tr.next().charAt(0) {
			case "p":
				tr.read();
				parseToken(tr).concat(parseToken(tr));
			case "r":
				tr.read();
				final n = Std.parseInt(tr.read());
				final s = parseToken(tr);
				final res = [];
				for (i in 0...n) {
					res.push(s);
				}
				res.flatten();
			case "i":
				final id = Std.parseInt(tr.read().substr(1));
				return [id];
			case _:
				throw "invalid prefix";
		}
	}

	static function lzss(ints:Array<Int>):Array<Int> {
		final res = [];
		var i = 0;
		while (i < 1024) {
			var maxFrom = 0;
			var maxLen = 0;
			// trace("next begins with " + ints[i]);
			for (from in 0...i) {
				if (ints[from] != ints[i])
					continue;
				final maxPossibleLen = 1024 - i;
				var len = 1;
				while (len < maxPossibleLen) {
					if (ints[from + len] == ints[i + len])
						len++;
					else
						break;
				}
				if (len > maxLen) {
					maxFrom = from;
					maxLen = len;
				}
			}
			// trace("matches from " + maxFrom + " for " + maxLen);
			if (maxLen == 0) {
				res.push(0);
				res.push(ints[i]);
				i++;
			} else {
				res.push(maxFrom + 1); // make it 1-indexed
				res.push(maxLen);
				i += maxLen;
			}
		}
		return res;
	}

	static function invLZSS(ints:Array<Int>):Array<Int> {
		final res = [];
		var i = 0;
		while (i < ints.length) {
			if (ints[i] == 0) {
				res.push(ints[i + 1]);
				i += 2;
			} else {
				final from = ints[i] - 1;
				final len = ints[i + 1];
				for (di in 0...len) {
					res.push(res[from + di]);
				}
				i += 2;
			}
		}
		return res;
	}

	// apply LZSS compression to the mapped animation data
	static function compressLZSS():Void {
		final lines = File.getContent("anims_mapped.txt").split("\n");
		final fo = File.write("anims_lzss.txt", false);
		var lineIndex = 0;
		for (line in lines) {
			if (++lineIndex % 1000 == 0)
				trace("read " + lineIndex + "/600560");
			if (line == "") {
				fo.writeString("\n");
				continue;
			}
			final tokens = line.split(" ");
			final ints = parseTokens(new TokenReader(tokens));
			final ints2 = lzss(ints);
			final ints3 = invLZSS(ints2);
			for (i in 0...1024) {
				if (ints[i] != ints3[i])
					throw "nope";
			}
			fo.writeString(ints2.join(" ") + "\n");
		}
	}

	// after LZSS compression similar patterns appear so try to reuse them
	static function compressLZSS2():Void {
		final lines = File.getContent("anims_lzss.txt").split("\n");

		final patternSet:Set<String> = new HashSet<String>();
		for (line in lines) {
			if (line == "")
				continue;
			final ints = line.split(" ");
			final ints2 = [];
			for (i in 0...ints.length) {
				if (i > 0 && i % 2 == 1 && ints[i - 1] == "0")
					continue;
				ints2.push(ints[i]);
			}
			patternSet.add(ints2.join(" "));
		}
		final numPatterns = patternSet.size();
		trace("num patterns: " + numPatterns);
		final patterns:Array<String> = [for (s in patternSet) s];
		patterns.sort((a, b) -> a.length - b.length);

		final fo = File.write("anims_lzss2.txt", false);
		fo.writeString(numPatterns + "\n\n");
		for (p in patterns) {
			fo.writeString(p + "\n");
		}
		fo.writeString("\n");
		final pindices = [];
		final nindices = [];
		for (line in lines) {
			if (line == "") {
				continue;
				fo.writeString("\n");
			}
			final ints = line.split(" ");
			final ints2 = [];
			final idxs = [];
			for (i in 0...ints.length) {
				if (i > 0 && i % 2 == 1 && ints[i - 1] == "0") {
					final idx = Std.parseInt(ints[i]);
					nindices.push(idx);
					idxs.push(idx);
					continue;
				}
				ints2.push(ints[i]);
			}
			final pattern = ints2.join(" ");
			final pindex = patterns.indexOf(pattern);
			pindices.push(pindex);
		}
		fo.writeString(pindices.join(" ") + "\n");
		fo.writeString(nindices.join(" ") + "\n");
	}

	// finally generates a png that contains the animation data
	static function compressAnims():Void {
		trace("generating anims.png...");
		final lines = File.getContent("anims_lzss2.txt").split("\n");
		final nums = [];
		for (l in lines) {
			if (l == "")
				continue;
			for (n in l.split(" ").map(Std.parseInt)) {
				nums.push(n);
			}
		}
		trace("nums: " + nums.length);
		final w = 2048;
		final h = 1096;
		if (nums.length > w * h)
			throw "nope";
		final bi = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
		final pixs = cast(bi.getRaster().getDataBuffer(), DataBufferInt).getData();
		for (i => n in nums) {
			if (n > 16777215)
				throw "nope " + i + " " + n;
			pixs[i] = n;
		}
		ImageIO.write(bi, "png", new java.io.File("anims.png"));
	}

	extern static inline function compInt(a:Int, b:Int):Int {
		return a < b ? -1 : a > b ? 1 : 0;
	}

	// compress ~level3 nodes into 16-bit ints
	static function compressSmalls():Void {
		final lines = File.getContent("graph_mapped.txt").split("\n");
		final fo = File.write("graph_compressed.txt", false);
		final nodes = [];
		nodes.push([[0], [1]]);
		var level = 0;
		var p00 = 1;
		for (l in lines) {
			final ints = l.split(" ").map(Std.parseInt);
			if (l == "")
				continue;
			if (ints.length != 4)
				throw "nope";
			if (p00 > 0 && ints[0] == 0) {
				level++;
				nodes.push([]);
			}
			p00 = ints[0];
			final node = [ints[0], ints[1], ints[2], ints[3]];
			nodes[level].push(node);
			if (level == 3) {
				function encodeLevel2(i:Int):Int {
					var res = 0;
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][0]][0]][0];
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][0]][1]][0];
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][1]][0]][0];
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][1]][1]][0];
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][0]][2]][0];
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][0]][3]][0];
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][1]][2]][0];
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][1]][3]][0];
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][2]][0]][0];
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][2]][1]][0];
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][3]][0]][0];
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][3]][1]][0];
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][2]][2]][0];
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][2]][3]][0];
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][3]][2]][0];
					res = res << 1 | nodes[0][nodes[1][nodes[2][i][3]][3]][0];
					return res;
				}
				fo.writeString(node.map(encodeLevel2).join(" ") + "\n");
			} else if (level > 3) {
				fo.writeString(node.join(" ") + "\n");
			}
		}
		fo.close();
	}

	static function readPixels(name:String):Array<Int> {
		final bi = ImageIO.read(new java.io.File(name));
		return [for (i in bi.getRGB(0, 0, bi.getWidth(), bi.getHeight(), null, 0, bi.getWidth())) i];
	}

	static function writePixels(name:String, pixels:Array<Array<Int>>):Void {
		final h = pixels.length;
		final w = pixels[0].length;
		final bi = new BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB);
		final pixs = cast(bi.getRaster().getDataBuffer(), DataBufferInt).getData();
		var idx = 0;
		for (i in 0...h)
			for (j in 0...w)
				pixs[idx++] = pixels[i][j];
		ImageIO.write(bi, name.split(".").slice(-1)[0], new java.io.File(name));
	}

	static function decodeTest():Void {
		final dec = new Decoder();

		trace("reading graph.png...");
		final graph = readPixels("graph.png");
		trace("reading anim.png...");
		final anim = readPixels("anim.png");
		trace("decoding graph...");
		dec.decodeGraph(graph);
		trace("decoding anim...");
		dec.decodeAnim(anim);

		function readFrame(level:Int, index:Int, x:Int, y:Int, pixels:Array<Array<Int>>):Void {
			if (level == 2) {
				var idx = 16;
				for (i in 0...4)
					for (j in 0...4)
						if (index & 1 << --idx != 0)
							pixels[y + i][x + j] = 0xffffffff;
			} else {
				final s = 1 << (level - 1);
				final node = dec.graph.nodeOfLevel(level, index);
				readFrame(level - 1, node.children[0], x, y, pixels);
				readFrame(level - 1, node.children[1], x + s, y, pixels);
				readFrame(level - 1, node.children[2], x, y + s, pixels);
				readFrame(level - 1, node.children[3], x + s, y + s, pixels);
			}
		}
		{
			final pixels = [for (i in 0...2048) [for (j in 0...2048) 0xff000000]];
			final frameIndex = 10000;
			final frame = dec.frames.restoreFrame(frameIndex);
			final pattern = 308;
			for (i in 0...16) {
				readFrame(9, frame[i][pattern], (i & 3) << 9, (i >> 2) << 9, pixels);
			}
			writePixels("frame_" + frameIndex + "_" + pattern + ".png", pixels);
		}
		// {
		// 	final pixels = [for (i in 0...512) [for (j in 0...512) 0xff000000]];
		// 	readFrame(9, 477173, 0, 0, pixels);
		// 	writePixels("graph_9_477173.png", pixels);
		// }

		// {
		// 	final w = 2048;
		// 	final h = 1096;
		// 	if (nums.length > w * h)
		// 		throw "nope";
		// 	final bi = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
		// 	final pixs = cast(bi.getRaster().getDataBuffer(), DataBufferInt).getData();
		// 	for (i => n in nums) {
		// 		if (n > 16777215)
		// 			throw "nope " + i + " " + n;
		// 		pixs[i] = n;
		// 	}
		// }
	}

	static function compressLocations():Void {
		trace("generating locations.png...");
		final lines = File.getContent("locations.txt").split("\n");
		final nums = [];
		for (l in lines) {
			if (l == "")
				continue;
			final ns = l.split(" ").map(Std.parseInt);
			assert(ns.length == 1 || ns.length == 3);
			if (ns.length == 1) {
				nums.push(ns[0]);
			} else {
				nums.push(ns[0] | ns[1] << 12);
				nums.push(ns[2]);
			}
		}
		trace("nums: " + nums.length);
		final w = 128;
		final h = 65;
		if (nums.length > w * h)
			throw "nope";
		final bi = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
		final pixs = cast(bi.getRaster().getDataBuffer(), DataBufferInt).getData();
		for (i => n in nums) {
			if (n > 16777215)
				throw "nope " + i + " " + n;
			pixs[i] = n;
		}
		ImageIO.write(bi, "png", new java.io.File("locations.png"));
	}

	static function main() {
		// compressRLE();
		// compressIDs();
		// compressSmalls();
		// compressGraph();
		// compressLZSS();
		// compressLZSS2();
		// compressAnims();
		compressLocations();

		// decodeTest();
	}
}
