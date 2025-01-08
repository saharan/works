import muun.la.Vec3;

class Neighbor {
	public var p1:Particle;
	public var p2:Particle;
	public var r:Float;
	public var w:Float;
	public var w2:Float;
	public final n:Vec3 = Vec3.zero;
	public var disabled:Bool = false;
	public var i1:Int = -1;
	public var i2:Int = -1;

	public function new() {
	}

	extern public inline function init(p1:Particle, p2:Particle):Void {
		this.p1 = p1;
		this.p2 = p2;
		i1 = p1.index;
		i2 = p2.index;
	}
}
