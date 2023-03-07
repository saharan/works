abstract GridIndex(Int) to Int {
	public static final NULL:GridIndex = new GridIndex(-1);

	@:allow(Grid)
	inline function new(index:Int) {
		this = index;
	}
}
