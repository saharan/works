package generator;

using haxe.EnumTools;

enum Chunk {
	Repeat(n:Int, chunk:Chunk);
	Single(id:Int);
	Pair(a:Chunk, b:Chunk);
}

class AnimBlock {
	public final chunks:Array<Chunk> = [];

	public function new() {
	}

	extern inline function last():Null<Chunk> {
		return chunks.length == 0 ? null : chunks[chunks.length - 1];
	}

	extern inline function setLast(chunk:Chunk):Void {
		chunks[chunks.length - 1] = chunk;
	}

	public function add(id:Int):Void {
		switch last() {
			case null:
				chunks.push(Single(id));
			case Repeat(n, chunk):
				if (chunk.equals(Single(id))) {
					setLast(Repeat(n + 1, chunk));
				} else {
					compress();
					chunks.push(Single(id));
				}
			case Single(id2):
				if (id == id2) {
					setLast(Repeat(2, Single(id)));
				} else {
					compress();
					chunks.push(Single(id));
				}
			case Pair(a, b):
				throw "this must not happen";
		}
		compress();
	}

	function compress():Void {
		var i = 0;
		while (i < chunks.length) {
			switch chunks[i] {
				case Repeat(n, Pair(a, b)):
					while (i + 2 < chunks.length && chunks[i + 1].equals(a) && chunks[i + 2].equals(b)) {
						chunks.splice(i + 1, 2);
						n++;
					}
					chunks[i] = Repeat(n, Pair(a, b));
				case _:
					if (i + 3 < chunks.length && chunks[i].equals(chunks[i + 2]) && chunks[i + 1].equals(chunks[i + 3])) {
						chunks[i] = Repeat(2, Pair(chunks[i], chunks[i + 1]));
						chunks.splice(i + 1, 3);
						i--;
					}
			}
			i++;
		}
	}

	public function toString():String {
		return chunks.map(chunkToString).join(" ");
	}

	static function chunkToString(chunk:Chunk):String {
		return switch chunk {
			case Repeat(n, chunk):
				"r " + n + " " + chunkToString(chunk);
			case Single(id):
				"i" + id;
			case Pair(a, b):
				"p " + chunkToString(a) + " " + chunkToString(b);
		}
	}
}
