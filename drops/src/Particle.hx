import muun.la.Vec3;

class Particle {
	public final pos:Vec3 = Vec3.zero;
	public final vel:Vec3 = Vec3.zero;
	public final n:Vec3 = Vec3.zero;
	public var density:Float = 0;
	public var p:Float = 0;
	public var index:Int = -1;
	public var grabbed:Bool = false;
	public var remove:Bool = false;
	public var kinematicVel:Vec3 = Vec3.zero;
	public var kinematicFor:Int = 0;

	public function new(x:Float, y:Float, z:Float) {
		pos.set(x, y, z);
	}
}
