import DragMode.ItemKind;
import muun.la.Vec2;

class Item {
	public final kind:ItemKind;
	public final v1:Vec2;
	public final v2:Vec2;
	public final v:Vec2;
	public final direction:Vec2;
	public final size:Float;

	public function new(x:Float, y:Float, dx:Float, dy:Float, size:Float, kind:ItemKind) {
		this.size = size;
		this.kind = kind;
		direction = Vec2.of(dx, dy);
		v = Vec2.of(x, y);
		v1 = v - direction * size;
		v2 = v + direction * size;
	}

	extern public inline function drag(pos:Vec2):Void {
		switch kind {
			case Wand:
				final delta = (pos - v).star;
				final diff = (delta.dot(direction) < 0 ? -1 : 1) * 0.08 * delta;
				direction <<= (direction + diff).normalized;
				v1 <<= pos - direction * size;
				v2 <<= pos + direction * size;
			case Fan:
				final delta = (pos - v).star;
				final dist = delta.length;
				final ang1 = Math.atan2(direction.y, direction.x);
				final ang2 = Math.atan2(delta.y, delta.x);
				var adiff = ang2 - ang1;
				if (adiff > Math.PI)
					adiff -= Math.PI * 2;
				else if (adiff < -Math.PI)
					adiff += Math.PI * 2;
				final newAng = ang1 + adiff * (1 - Math.exp(-dist * 0.05));
				direction <<= Vec2.of(Math.cos(newAng), Math.sin(newAng));
				v1 <<= pos - direction * size;
				v2 <<= pos + direction * size;
			case Needle:
				final delta = (pos - (v1 * 0.75 + v2 * 0.25));
				final dist = delta.length;
				final ang1 = Math.atan2(direction.y, direction.x);
				final ang2 = Math.atan2(delta.y, delta.x);
				var adiff = ang2 - ang1;
				if (adiff > Math.PI)
					adiff -= Math.PI * 2;
				else if (adiff < -Math.PI)
					adiff += Math.PI * 2;
				final newAng = ang1 + adiff * (1 - Math.exp(-dist * 0.05));
				direction <<= Vec2.of(Math.cos(newAng), Math.sin(newAng));
				v1 <<= pos - direction * size * 0.5;
				v2 <<= pos + direction * size * 1.5;
		}
		v <<= (v1 + v2) * 0.5;
	}
}
