import js.lib.Int32Array;

typedef Array3<A> = Array<Array<Array<A>>>;
typedef Face<A> = Array<Array<A>>; // dim(3), dir(2)

typedef Listener = {
	var array:Int32Array;
	var offset:Int;
}

typedef Listeners = Array<Listener>;

typedef Vertex = {
	var cell:Cell;
	var idx:Int; // index in cell, from 0 to 7
	var dir:Array<Int>;
	var pos:VertexPosition;
	var group:Array<Vertex>;
	var groupIndices:Array<Int>;
	var groupIndicesListeners:Listeners;
	var faceGroupIndices:Face<Array<Int>>;
	var faceGroupIndicesListeners:Face<Listeners>;
}

typedef Cell = {
	var idx:Array<Int>;
	var idx1d:Int;
	var verts:Array3<Vertex>;
	var poss:Array3<VertexPosition>;
	var conns:Face<Bool>;
	var adj:Face<Cell>;
}

typedef VertexPosition = {
	var idx:Array<Int>;
	var cells:Array3<Cell>;
	var needUpdate:Bool;
}

class MeshManager {
	public final sizeX:Int;
	public final sizeY:Int;
	public final sizeZ:Int;

	public final poss:Array3<VertexPosition> = [];
	public final cells:Array3<Cell> = [];

	public function new(sizeX:Int, sizeY:Int, sizeZ:Int) {
		this.sizeX = sizeX;
		this.sizeY = sizeY;
		this.sizeZ = sizeZ;
		cells = make((i, j, k) -> {
			idx: [i, j, k],
			idx1d: k + sizeZ * (j + sizeY * i),
			verts: null,
			poss: null,
			conns: [[true, true], [true, true], [true, true]],
			adj: null
		});
		poss = make((i, j, k) -> {
			idx: [i, j, k],
			cells: make(2, 2, 2, (di, dj, dk) -> {
				access(cells, i - 1 + di, j - 1 + dj, k - 1 + dk);
			}),
			needUpdate: true
		});
		loop((i, j, k) -> {
			final cell = cells[i][j][k];
			cell.verts = make(2, 2, 2, (di, dj, dk) -> {
				cell: cell,
				idx: di | dj << 1 | dk << 2,
				dir: [di, dj, dk],
				pos: access(poss, i + di, j + dj, k + dk),
				group: null,
				groupIndices: null,
				groupIndicesListeners: [],
				faceGroupIndices: null,
				faceGroupIndicesListeners: make(3, 2, (i, j) -> [])
			});
			cell.poss = make(2, 2, 2, (di, dj, dk) -> cell.verts[di][dj][dk].pos);
			cell.adj = [
				[access(cells, i - 1, j, k), access(cells, i + 1, j, k)],
				[access(cells, i, j - 1, k), access(cells, i, j + 1, k)],
				[access(cells, i, j, k - 1), access(cells, i, j, k + 1)]
			];
		});
		loop((i, j, k) -> {
			updateGroups(poss[i][j][k]);
		});
	}

	public function update():Bool {
		var updated = false;
		loop((i, j, k) -> {
			final pos = poss[i][j][k];
			if (pos.needUpdate) {
				updated = true;
				updateGroups(pos);
			}
		});
		return updated;
	}

	public function cut(i:Int, j:Int, k:Int, dim:Int, dir:Int):Void {
		final cell = access(cells, i, j, k);
		if (!cell.conns[dim][dir])
			return;
		cell.conns[dim][dir] = false;
		cell.adj[dim][dir].conns[dim][dir ^ 1] = false;
		final ps = cell.poss;
		switch dim {
			case 0:
				ps[dir][0][0].needUpdate = true;
				ps[dir][0][1].needUpdate = true;
				ps[dir][1][0].needUpdate = true;
				ps[dir][1][1].needUpdate = true;
			case 1:
				ps[0][dir][0].needUpdate = true;
				ps[0][dir][1].needUpdate = true;
				ps[1][dir][0].needUpdate = true;
				ps[1][dir][1].needUpdate = true;
			case 2:
				ps[0][0][dir].needUpdate = true;
				ps[0][1][dir].needUpdate = true;
				ps[1][0][dir].needUpdate = true;
				ps[1][1][dir].needUpdate = true;
			case _:
				throw "invalid dimension";
		}
	}

	function updateGroups(pos:VertexPosition):Void {
		final visited = make(2, 2, 2, (i, j, k) -> false);
		loop(2, 2, 2, (di, dj, dk) -> {
			if (!visited[di][dj][dk]) {
				final list = [];
				dfs(visited, list, di, dj, dk, pos.cells);
				final indices = [];
				for (v in list) {
					indices.push(v.cell.idx1d << 3 | v.idx);
					v.group = list;
				}
				while (indices.length < 8)
					indices.push(-1);
				for (v in list) {
					v.groupIndices = indices;
					for (l in v.groupIndicesListeners) {
						final a = l.array;
						var idx = l.offset;
						a[idx++] = indices[0];
						a[idx++] = indices[1];
						a[idx++] = indices[2];
						a[idx++] = indices[3];
						a[idx++] = indices[4];
						a[idx++] = indices[5];
						a[idx++] = indices[6];
						a[idx++] = indices[7];
					}
				}
				final faceIndices = [[[], []], [[], []], [[], []]];
				for (v in list) {
					final cidx = v.cell.idx1d << 3;
					faceIndices[0][v.dir[0]].push(cidx | (v.dir[0] << 2));
					faceIndices[1][v.dir[1]].push(cidx | (1 | v.dir[1] << 2));
					faceIndices[2][v.dir[2]].push(cidx | (2 | v.dir[2] << 2));
				}
				for (dim in 0...3) {
					for (dir in 0...2) {
						final indices = faceIndices[dim][dir];
						while (indices.length < 4)
							indices.push(-1);
					}
				}
				for (v in list) {
					v.faceGroupIndices = faceIndices;
					loop(3, 2, (dim, dir) -> {
						for (l in v.faceGroupIndicesListeners[dim][dir]) {
							final a = l.array;
							var idx = l.offset;
							a[idx++] = faceIndices[dim][dir][0];
							a[idx++] = faceIndices[dim][dir][1];
							a[idx++] = faceIndices[dim][dir][2];
							a[idx++] = faceIndices[dim][dir][3];
						}
					});
				}
			}
		});
		pos.needUpdate = false;
	}

	function dfs(visited:Array3<Bool>, list:Array<Vertex>, di:Int, dj:Int, dk:Int, cells:Array3<Cell>):Void {
		visited[di][dj][dk] = true;
		final cell = cells[di][dj][dk];
		list.push(cell.verts[di ^ 1][dj ^ 1][dk ^ 1]);
		if (cell.conns[0][di ^ 1] && !visited[di ^ 1][dj][dk])
			dfs(visited, list, di ^ 1, dj, dk, cells);
		if (cell.conns[1][dj ^ 1] && !visited[di][dj ^ 1][dk])
			dfs(visited, list, di, dj ^ 1, dk, cells);
		if (cell.conns[2][dk ^ 1] && !visited[di][dj][dk ^ 1])
			dfs(visited, list, di, dj, dk ^ 1, cells);
	}

	overload extern inline function make<A>(numX:Int, numY:Int, numZ:Int, f:(i:Int, j:Int, k:Int) -> A):Array3<A> {
		return [for (i in 0...numX) [for (j in 0...numY) [for (k in 0...numZ) {
			f(i, j, k);
		}]]];
	}

	overload extern inline function make<A>(numX:Int, numY:Int, f:(i:Int, j:Int) -> A):Array<Array<A>> {
		return [for (i in 0...numX) [for (j in 0...numY) {
			f(i, j);
		}]];
	}

	overload extern inline function make<A>(f:(i:Int, j:Int, k:Int) -> A):Array3<A> {
		return make(sizeX, sizeY, sizeZ, f);
	}

	overload extern inline function loop(numX:Int, numY:Int, numZ:Int, f:(i:Int, j:Int, k:Int) -> Void):Void {
		for (i in 0...numX) {
			for (j in 0...numY) {
				for (k in 0...numZ) {
					f(i, j, k);
				}
			}
		}
	}

	overload extern inline function loop(numX:Int, numY:Int, f:(i:Int, j:Int) -> Void):Void {
		for (i in 0...numX) {
			for (j in 0...numY) {
				f(i, j);
			}
		}
	}

	overload extern inline function loop(f:(i:Int, j:Int, k:Int) -> Void):Void {
		return loop(sizeX, sizeY, sizeZ, f);
	}

	function access<A>(array:Array3<A>, i:Int, j:Int, k:Int):A {
		final i2 = (i % sizeX + sizeX) % sizeX;
		final j2 = (j % sizeY + sizeY) % sizeY;
		final k2 = (k % sizeZ + sizeZ) % sizeZ;
		return array[i2][j2][k2];
	}
}
