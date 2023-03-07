package phys;

class Circle extends Shape {
	public var r:Float;

	public function new(r:Float) {
		super(Circle(this));
		this.r = r;
	}

	override function computeMass():Void {
		area = Math.PI * r * r;
		inertia = r * r / 2;
	}

	override function updateAABB():Void {
		aabb.set(p - r, p + r);
	}
}
