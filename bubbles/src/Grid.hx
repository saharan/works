import haxe.ds.Vector;

class Grid<V> {
	public static inline final HASH_SHIFT:Int = 20;
	public static inline final HASH_SIZE:Int = 1 << HASH_SHIFT;
	public static inline final HASH_MASK:Int = HASH_SIZE - 1;

	final times:Vector<Int> = new Vector<Int>(HASH_SIZE);
	final firsts:Vector<VertexIndex> = new Vector<VertexIndex>(HASH_SIZE);
	final nexts:Array<VertexIndex> = [];
	final vertices:Array<V> = [];
	final pool:Array<VertexIndex> = [];

	var time:Int = 0;

	public function new() {
		for (i in 0...HASH_SIZE) {
			times[i] = 0;
			firsts[i] = VertexIndex.NULL;
		}
	}

	public function createVertex(v:V = null):VertexIndex {
		if (pool.length > 0) {
			final vi = pool.pop();
			vertices[vi] = v;
			return vi;
		}
		var i = nexts.length;
		nexts.push(VertexIndex.NULL);
		vertices.push(v);
		return new VertexIndex(i);
	}

	public function setVertex(vi:VertexIndex, v:V):Void {
		vertices[vi] = v;
	}

	public function destroyVertex(vi:VertexIndex):Void {
		nexts[vi] = VertexIndex.NULL;
		vertices[vi] = null;
		pool.push(vi);
	}

	public function destroyVertices():Void {
		nexts.resize(0);
		vertices.resize(0);
		time++;
	}

	public function clear():Void {
		time++;
	}

	extern public inline function getIndex(gx:Int, gy:Int):GridIndex {
		var hash = 17;
		hash = (hash << 5) - hash + gx;
		hash = (hash << 5) - hash + gy;
		return new GridIndex(hash & HASH_MASK);
	}

	extern public inline function register(vi:VertexIndex, gi:GridIndex):Void {
		if (times[gi] != time) {
			times[gi] = time;
			firsts[gi] = VertexIndex.NULL;
		}
		nexts[vi] = firsts[gi];
		firsts[gi] = vi;
	}

	extern public inline function forEach(gi:GridIndex, f:(vi:VertexIndex, v:V) -> Void):Void {
		if (times[gi] != time)
			return;
		var vi = firsts[gi];
		while (vi != VertexIndex.NULL) {
			f(vi, vertices[vi]);
			vi = nexts[vi];
		}
	}
}
