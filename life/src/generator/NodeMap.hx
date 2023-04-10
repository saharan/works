package generator;

import haxe.ds.Vector;

class NodeMap {
	static inline final MAP_SIZE = 0x4000000;
	static inline final MAP_MASK = MAP_SIZE - 1;

	final data:Vector<Node>;
	final pool:Array<Node> = [];

	var gcTime:Int = 0;

	public function new() {
		data = new Vector<Node>(MAP_SIZE);
	}

	public function request(e00:Node, e01:Node, e10:Node, e11:Node):Node {
		final index = Node.hash(e00, e01, e10, e11) & MAP_MASK;
		var n = data[index];
		while (n != null) {
			if (n.e00 == e00 && n.e01 == e01 && n.e10 == e10 && n.e11 == e11)
				return n;
			n = n.nextInSameIndex;
		}
		final res = pool.length == 0 ? Node.create(e00, e01, e10, e11) : Node.createAt(pool.pop(), e00, e01, e10, e11);
		assert(!res.immortal && !res.marked && res.nextCached == null);
		res.nextInSameIndex = data[index];
		data[index] = res;
		return res;
	}

	public function analyze():Void {
		var counts = [for (i in 0...100) 0];
		for (i in 0...MAP_SIZE) {
			var count = 0;
			var n = data[i];
			while (n != null) {
				count++;
				n = n.nextInSameIndex;
			}
			counts[count]++;
		}
		trace(counts);
	}

	function mark(n:Node):Void {
		if (n.gcMark == gcTime)
			return;
		n.gcMark = gcTime;
		if (n.level > 0) {
			mark(n.e00);
			mark(n.e01);
			mark(n.e10);
			mark(n.e11);
			if (n.nextCached != null)
				mark(n.nextCached);
		}
	}

	public function shouldGC():Bool {
		return pool.length == 0;
	}

	public function gc(root:Node):Void {
		gcTime++;
		mark(root);
		var removed = 0;
		var left = 0;
		for (i in 0...MAP_SIZE) {
			var n = data[i];
			final ns = [];
			while (n != null) {
				final next = n.nextInSameIndex;
				if (n.marked || n.gcMark == gcTime || n.immortal)
					ns.push(n);
				else {
					removed++;
					n.nextCached = null;
					n.e00 = null;
					n.e01 = null;
					n.e10 = null;
					n.e11 = null;
					pool.push(n);
				}
				n = next;
			}
			left += ns.length;
			ns.reverse();
			data[i] = null;
			for (n in ns) {
				n.nextInSameIndex = data[i];
				data[i] = n;
			}
		}
		trace("GC done, removed: " + removed + ", left: " + left);
	}
}
