import muun.la.Vec3;
import muun.la.Vec2;

class Particle {
	public final pos:Vec2;
	public final vel:Vec2;
	public final color:Vec3;
	public var dead:Bool = false;
	public var time:Int = 0;
	public var size:Float;

	public function new(pos:Vec2, color:Vec3) {
		this.pos = pos.copy();
		this.color = color;
		vel = Vec2.of(rand(), rand()) * 4;
		size = 1 + Math.random();
	}

	public function update():Void {
		time++;
		vel *= 0.9;
		size *= 0.9;
		pos += vel;
		if (time > 30)
			dead = true;
	}

	static inline function rand():Float {
		return (Math.random() + Math.random() + Math.random() + Math.random() + Math.random() + Math.random() + Math.random() +
			Math.random() + Math.random() - 4.5) * 2 / 3;
	}
}
