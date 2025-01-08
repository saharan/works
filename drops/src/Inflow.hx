import muun.la.Vec3;

class Inflow {
	public final center:Vec3 = Vec3.zero;
	public final side1:Vec3 = Vec3.zero;
	public final side2:Vec3 = Vec3.zero;
	public final dir:Vec3 = Vec3.zero;
	public var radius:Float = 0;
	public var vel:Float = 0;

	var lastAdded:Float = 0;

	public function new(x:Float, y:Float, z:Float, side1:Vec3, side2:Vec3, dir:Vec3, radius:Float, vel:Float) {
		center.set(x, y, z);
		this.side1 <<= side1;
		this.side2 <<= side2;
		this.dir <<= dir;
		this.radius = radius;
		this.vel = vel;
	}

	public function update(substeps:Int, addParticle:Particle -> Void) {
		if (vel <= 0)
			return;
		lastAdded += vel;
		final kinematicLayers = 2;
		final kinematicFor = Math.ceil(kinematicLayers * Main.INTERVAL / vel * substeps);
		while (lastAdded > Main.INTERVAL) {
			lastAdded -= Main.INTERVAL;
			final r = Math.ceil(radius);
			for (i in -r...r + 1) {
				for (j in -r...r + 1) {
					if (i * i + j * j <= r * r) {
						final pos = center + (i * side1 + j * side2) * Main.INTERVAL + lastAdded * dir;
						final p = new Particle(pos.x, pos.y, pos.z);
						p.vel <<= dir * vel;
						p.kinematicVel <<= dir * vel;
						p.kinematicFor = kinematicFor;
						addParticle(p);
					}
				}
			}
		}
	}
}
