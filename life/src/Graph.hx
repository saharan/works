typedef Node = {
	indexInLevel:Int,
	level:Int,
	pop:Int,
	children:Array<Int>
}

class Graph {
	public final nodes:Array<Array<Node>> = [];
	public var maxPopulation(default, null) = 0;

	public function new() {
		for (i in 0...7) {
			nodes.push([]);
		}
	}

	public function add(level:Int, indices:Array<Int>):Void {
		assert(level >= 3);
		final ps = level == 3 ? null : nodes[level - 4];
		final ns = nodes[level - 3];
		final pop = ps == null ? sum(indices.map(i -> popcount(i))) : sum(indices.map(i -> ps[i].pop));
		maxPopulation = max(maxPopulation, pop);
		ns.push({
			indexInLevel: ns.length,
			level: level,
			pop: pop,
			children: indices
		});
	}

	public function nodesOfLevel(level:Int):Array<Node> {
		assert(level >= 3);
		return nodes[level - 3];
	}

	public function nodeOfLevel(level:Int, index:Int):Node {
		return nodesOfLevel(level)[index];
	}

	public function numNodesOfLevel(level:Int):Int {
		return nodesOfLevel(level).length;
	}

	public inline function getBit(level:Int, index:Int, x:Int, y:Int):Int {
		assert(level >= 2 && level <= 9);
		assert(x >= 0 && x < 1 << level);
		assert(y >= 0 && y < 1 << level);

		while (level > 2) {
			final size = 1 << (level - 1);
			final node = nodeOfLevel(level, index);
			if (y < size) {
				if (x < size) {
					index = node.children[0];
				} else {
					index = node.children[1];
					x -= size;
				}
			} else {
				y -= size;
				if (x < size) {
					index = node.children[2];
				} else {
					index = node.children[3];
					x -= size;
				}
			}
			level--;
		}
		assert(x >= 0 && x < 4);
		assert(y >= 0 && y < 4);
		final bitIndex = 15 ^ (y << 2 | x);
		return index >> bitIndex & 1;
	}
}
