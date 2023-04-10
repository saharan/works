package generator;

class Field {
	public final map:NodeMap = new NodeMap();

	public var root:Node = null;

	public function new(size:Int) {
		init(size);
	}

	public function init(size:Int):Void {
		var n = 2;
		root = map.request(Node.DEAD, Node.DEAD, Node.DEAD, Node.DEAD);
		// root = map.request(Node.DEAD, Node.DEAD, Node.DEAD, Node.ALIVE);
		root = map.request(root, root, root, root);
		while (n < size) {
			root = map.request(root, root, root, root);
			n *= 2;
		}
	}
}
