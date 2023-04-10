package generator;

class Node {
	public var nextInSameIndex:Node = null;
	public var e00:Node;
	public var e01:Node;
	public var e10:Node;
	public var e11:Node;
	public var nextCached:Node = null;
	public var level:Int;
	public var pop:Int;
	public var id:Int;
	public var immortal:Bool = false;
	public var gcMark:Int = -1;

	public static var idCount(default, null) = 0;

	public static final DEAD:Node = new Node(null, null, null, null, 0, 0);
	public static final ALIVE:Node = new Node(null, null, null, null, 0, 1);

	public var marked:Bool = false;

	function new(e00:Node, e01:Node, e10:Node, e11:Node, level:Int, pop:Int) {
		id = ++idCount;
		init(e00, e01, e10, e11, level, pop);
	}

	function init(e00:Node, e01:Node, e10:Node, e11:Node, level:Int, pop:Int) {
		this.e00 = e00;
		this.e01 = e01;
		this.e10 = e10;
		this.e11 = e11;
		this.level = level;
		this.pop = pop != -1 ? pop : e00.pop + e01.pop + e10.pop + e11.pop;
	}

	public function toString():String {
		return id + " " + level + " " + pop + (level == 0 ? "" : " " + e00.id + " " + e01.id + " " + e10.id + " " + e11.id);
	}

	public static function makeImmortal(n:Node):Void {
		if (n.immortal)
			return;
		n.immortal = true;
		if (n.level > 0) {
			makeImmortal(n.e00);
			makeImmortal(n.e01);
			makeImmortal(n.e10);
			makeImmortal(n.e11);
		}
		if (n.nextCached != null) {
			makeImmortal(n.nextCached);
		}
	}

	public static function create(e00:Node, e01:Node, e10:Node, e11:Node):Node {
		return new Node(e00, e01, e10, e11, e00.level + 1, e00.pop + e01.pop + e10.pop + e11.pop);
	}

	public static function createAt(n:Node, e00:Node, e01:Node, e10:Node, e11:Node):Node {
		n.init(e00, e01, e10, e11, e00.level + 1, e00.pop + e01.pop + e10.pop + e11.pop);
		return n;
	}

	extern public static inline function hash(e00:Node, e01:Node, e10:Node, e11:Node):Int {
		var res = 7;
		res = (res << 5) - res + e00.id;
		res = (res << 5) - res + e01.id;
		res = (res << 5) - res + e10.id;
		res = (res << 5) - res + e11.id;
		return res;
	}

	public function next(map:NodeMap):Node {
		if (nextCached != null)
			return nextCached;
		assert(level > 1);
		nextCached = if (level == 2) {
			final p00 = e00.e00.pop;
			final p01 = e00.e01.pop;
			final p02 = e01.e00.pop;
			final p03 = e01.e01.pop;
			final p10 = e00.e10.pop;
			final p11 = e00.e11.pop;
			final p12 = e01.e10.pop;
			final p13 = e01.e11.pop;
			final p20 = e10.e00.pop;
			final p21 = e10.e01.pop;
			final p22 = e11.e00.pop;
			final p23 = e11.e01.pop;
			final p30 = e10.e10.pop;
			final p31 = e10.e11.pop;
			final p32 = e11.e10.pop;
			final p33 = e11.e11.pop;
			final n00 = p00 << 3 | p01 << 2 | p10 << 1 | p11;
			final n01 = p01 << 3 | p02 << 2 | p11 << 1 | p12;
			final n02 = p02 << 3 | p03 << 2 | p12 << 1 | p13;
			final n10 = p10 << 3 | p11 << 2 | p20 << 1 | p21;
			final n11 = p11 << 3 | p12 << 2 | p21 << 1 | p22;
			final n12 = p12 << 3 | p13 << 2 | p22 << 1 | p23;
			final n20 = p20 << 3 | p21 << 2 | p30 << 1 | p31;
			final n21 = p21 << 3 | p22 << 2 | p31 << 1 | p32;
			final n22 = p22 << 3 | p23 << 2 | p32 << 1 | p33;
			var s0 = ~(n00 | n01);
			var s1 = n00 ^ n01;
			var s2 = n00 & n01;
			var s3 = n02 & s2;
			s2 = (s2 & ~n02) | (s1 & n02);
			s1 = (s1 & ~n02) | (s0 & n02);
			s0 &= ~n02;
			s3 = (s3 & ~n10) | (s2 & n10);
			s2 = (s2 & ~n10) | (s1 & n10);
			s1 = (s1 & ~n10) | (s0 & n10);
			s0 &= ~n10;
			s3 = (s3 & ~n12) | (s2 & n12);
			s2 = (s2 & ~n12) | (s1 & n12);
			s1 = (s1 & ~n12) | (s0 & n12);
			s0 &= ~n12;
			s3 = (s3 & ~n20) | (s2 & n20);
			s2 = (s2 & ~n20) | (s1 & n20);
			s1 = (s1 & ~n20) | (s0 & n20);
			s0 &= ~n20;
			s3 = (s3 & ~n21) | (s2 & n21);
			s2 = (s2 & ~n21) | (s1 & n21);
			s1 = (s1 & ~n21) | (s0 & n21);
			s3 = (s3 & ~n22) | (s2 & n22);
			s2 = (s2 & ~n22) | (s1 & n22);
			final n = s3 | (s2 & n11);
			final da = [DEAD, ALIVE];
			map.request(da[n >> 3 & 1], da[n >> 2 & 1], da[n >> 1 & 1], da[n & 1]);
		} else {
			final t00 = map.request(e00.e00.e11, e00.e01.e10, e00.e10.e01, e00.e11.e00);
			final t01 = map.request(e00.e01.e11, e01.e00.e10, e00.e11.e01, e01.e10.e00);
			final t02 = map.request(e01.e00.e11, e01.e01.e10, e01.e10.e01, e01.e11.e00);
			final t10 = map.request(e00.e10.e11, e00.e11.e10, e10.e00.e01, e10.e01.e00);
			final t11 = map.request(e00.e11.e11, e01.e10.e10, e10.e01.e01, e11.e00.e00);
			final t12 = map.request(e01.e10.e11, e01.e11.e10, e11.e00.e01, e11.e01.e00);
			final t20 = map.request(e10.e00.e11, e10.e01.e10, e10.e10.e01, e10.e11.e00);
			final t21 = map.request(e10.e01.e11, e11.e00.e10, e10.e11.e01, e11.e10.e00);
			final t22 = map.request(e11.e00.e11, e11.e01.e10, e11.e10.e01, e11.e11.e00);
			final n00 = map.request(t00, t01, t10, t11).next(map);
			final n01 = map.request(t01, t02, t11, t12).next(map);
			final n10 = map.request(t10, t11, t20, t21).next(map);
			final n11 = map.request(t11, t12, t21, t22).next(map);
			map.request(n00, n01, n10, n11);
		}
		if (immortal)
			makeImmortal(nextCached);
		return nextCached;
	}
}
