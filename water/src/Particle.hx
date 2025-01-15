import muun.la.Mat2;
import muun.la.Vec2;
import muun.la.Vec3;

class Particle {
	public final pos:Vec2 = Vec2.zero;
	public final vel:Vec2 = Vec2.zero;
	public final def:Mat2 = Mat2.id;
	public var mass:Float;
	public var v0:Float;
	public var volume:Float;
	public var jacobian:Float;
	public final affineVel:Mat2 = Mat2.zero; // corresponds to C in APIC
	public var gx:Int = 1;
	public var gy:Int = 1;
	public final uv:Vec2 = Vec2.zero;
	public final uvSize:Vec2 = Vec2.one;
	public var isFluid:Bool = false;

	public function new(p:Vec2, m:Float, v:Float) {
		pos <<= p;
		mass = m;
		v0 = v;
		volume = v;
		jacobian = 1;
	}
}
