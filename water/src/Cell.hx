import muun.la.Vec2;
import muun.la.Vec3;

class Cell {
	public final tmp:Vec2 = Vec2.zero;
	public final pos:Vec2 = Vec2.zero;
	public final momentum:Vec2 = Vec2.zero;
	public final dmomentum:Vec2 = Vec2.zero;
	public final velocity:Vec2 = Vec2.zero;
	public var mass:Float = 0;
	public var mass2:Float = 0;
	public var color:Float = 0;
	public final gc:Vec2 = Vec2.zero;
	public final n:Vec2 = Vec2.zero;

	public var distance:Float = 0;
	public final normal:Vec2 = Vec2.zero;
	public var nearBoundary:Bool = false;

	public function new() {
	}

	public inline function init(p:Vec2):Void {
		pos <<= p;
		momentum <<= Vec2.zero;
		dmomentum <<= Vec2.zero;
		velocity <<= Vec2.zero;
		mass = 0;
		mass2 = 0;
		color = 0;
		distance = 0;
		gc <<= Vec2.zero;
		n <<= Vec2.zero;
		normal <<= Vec2.zero;
		nearBoundary = false;
	}
}
