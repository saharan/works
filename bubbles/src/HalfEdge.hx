class HalfEdge {
	public var v(default, null):Vertex;
	public var e:Edge = null;
	public var prev(default, null):HalfEdge = null;
	public var next(default, null):HalfEdge = null;
	public var twin(default, null):HalfEdge = null;
	public var bubble:Bubble = null;

	static var idCount = 0;

	public final id = ++idCount;

	public function new(v:Vertex) {
		this.v = v;
		v.e = this;
	}

	public function makeTwin(v2:Vertex):HalfEdge {
		final e = new HalfEdge(v2);
		twin = e;
		e.twin = this;
		return e;
	}

	public function changeRoot(v:Vertex):Void {
		this.v = v;
		v.e = this;
	}

	public function setNext(edge:HalfEdge):HalfEdge {
		if (this == edge)
			throw "cannot set self to next";
		next = edge;
		if (next != null)
			next.prev = this;
		return edge;
	}

	public function setPrev(edge:HalfEdge):HalfEdge {
		if (this == edge)
			throw "cannot set self to prev";
		prev = edge;
		if (prev != null)
			prev.next = this;
		return edge;
	}
}
