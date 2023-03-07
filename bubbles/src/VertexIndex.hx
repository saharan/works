abstract VertexIndex(Int) to Int {
	public static final NULL:VertexIndex = new VertexIndex(-1);

	@:allow(Grid)
	inline function new(index:Int) {
		this = index;
	}
}
