import muun.la.Mat3;
import muun.la.Quat;
import muun.la.Vec3;

class Marimo {
	public final pos:Vec3 = Vec3.zero;
	public final vel:Vec3 = Vec3.zero;
	public final avel:Vec3 = Vec3.zero;
	public final q:Quat = Quat.id;
	public final rot:Mat3 = Mat3.id;
	public var radius(default, set):Float;
	public var invI:Float = 0;

	public function new(radius:Float) {
		this.radius = radius;
	}

	function set_radius(r:Float):Float {
		radius = r;
		invI = 1 / (2 / 5 * radius * radius);
		return radius;
	}

	public function update():Void {
		pos += vel;
		if (avel.lengthSq > 0) {
			final ang = avel.length;
			final axis = avel * (1 / ang);
			final dq = Quat.rot(ang, axis);
			q <<= dq * q;
			rot <<= q.toMat3();
		}
	}
}
