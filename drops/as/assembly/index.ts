let numN: i32 = 0;
let numP: i32 = 0;

// from Main.hx
const INTERVAL: f32 = 0.3;
const RE_RATIO: f32 = 2.1;
const INV_RE_RATIO: f32 = 1 / RE_RATIO;
const RE_FATTEN_SCALE: f32 = 1.1;
const RE: f32 = INTERVAL * RE_RATIO;
const RE_FAT: f32 = RE * RE_FATTEN_SCALE;
const INV_RE: f32 = 1 / RE;
const INV_RE_FAT: f32 = 1 / RE_FAT;
const RE2: f32 = RE * RE;
const RE2_FAT: f32 = RE_FAT * RE_FAT;

const B4 = 2;
const B16 = 4;

const MAX_PARTICLES: i32 = 2 << 16;
const PARTICLE_STRIDE: i32 = 11 << B4; // in bytes, x4 for f32
const P_PX: i32 = 0 << B4;
const P_PY: i32 = 1 << B4;
const P_PZ: i32 = 2 << B4;
const P_VX: i32 = 3 << B4;
const P_VY: i32 = 4 << B4;
const P_VZ: i32 = 5 << B4;
const P_NX: i32 = 6 << B4;
const P_NY: i32 = 7 << B4;
const P_NZ: i32 = 8 << B4;
const P_D: i32 = 9 << B4;
const P_P: i32 = 10 << B4;
const ps = heap.alloc(MAX_PARTICLES * PARTICLE_STRIDE);

// neighbors
const MAX_NEIGHBORS: i32 = 1 << 20;
const NEIGHBOR_STRIDE: i32 = 7 << B4; // in bytes, x4 for f32
const N_P1: i32 = 0 << B4;
const N_P2: i32 = 1 << B4;
const N_R: i32 = 2 << B4;
const N_W: i32 = 3 << B4;
const N_NX: i32 = 4 << B4;
const N_NY: i32 = 5 << B4;
const N_NZ: i32 = 6 << B4;
const ns = heap.alloc(MAX_NEIGHBORS * NEIGHBOR_STRIDE);

// vectorized neighbors
const MAX_VNEIGHBORS: i32 = (MAX_NEIGHBORS >> 2) + 1;
const VNEIGHBOR_STRIDE: i32 = 7 << B16; // in bytes, x16 for v128
const VN_P1: i32 = 0 << B16;
const VN_P2: i32 = 1 << B16;
const VN_W: i32 = 2 << B16;
const VN_WNX: i32 = 3 << B16;
const VN_WNY: i32 = 4 << B16;
const VN_WNZ: i32 = 5 << B16;
const VN_RVN: i32 = 6 << B16;
const vns = heap.alloc(MAX_VNEIGHBORS * VNEIGHBOR_STRIDE); // vectorized neighbors

const HASH_ODD: i32 = 0x9e3779b9;
const HASH_ADD: i32 = 0x2d1c40e2;
const HASH_SHIFT: i32 = 18;
const HASH_SIZE: i32 = 1 << HASH_SHIFT;
const HASH_MASK: i32 = HASH_SIZE - 1;
const CELL_CAPACITY_SHIFT: i32 = 7;
const CELL_CAPACITY: i32 = 1 << CELL_CAPACITY_SHIFT;
const gridData = heap.alloc((HASH_SIZE << CELL_CAPACITY_SHIFT) << B4);
const gridSizes = heap.alloc(HASH_SIZE << B4); // in bytes, x4 for i32

export function clear(): void {
	numP = 0;
	numN = 0;
}

export function addParticle(x: f32, y: f32, z: f32, vx: f32, vy: f32, vz: f32): void {
	let p = ps + numP * PARTICLE_STRIDE;
	f32.store(p, x, P_PX);
	f32.store(p, y, P_PY);
	f32.store(p, z, P_PZ);
	f32.store(p, vx, P_VX);
	f32.store(p, vy, P_VY);
	f32.store(p, vz, P_VZ);
	f32.store(p, 0, P_NX);
	f32.store(p, 0, P_NY);
	f32.store(p, 0, P_NZ);
	f32.store(p, 0, P_D);
	f32.store(p, 0, P_P);
	numP++;
}

export function particles(): usize {
	return ps;
}

function makef32x4(x: f32, y: f32, z: f32, w: f32): v128 {
	let res: v128 = f32x4.splat(0);
	res = f32x4.replace_lane(res, 0, x);
	res = f32x4.replace_lane(res, 1, y);
	res = f32x4.replace_lane(res, 2, z);
	res = f32x4.replace_lane(res, 3, w);
	return res;
}

function makei32x4(x: i32, y: i32, z: i32, w: i32): v128 {
	let res: v128 = i32x4.splat(0);
	res = i32x4.replace_lane(res, 0, x);
	res = i32x4.replace_lane(res, 1, y);
	res = i32x4.replace_lane(res, 2, z);
	res = i32x4.replace_lane(res, 3, w);
	return res;
}

function cellIndexi32x4(x: v128, y: v128, z: v128): v128 {
	let hash = x;
	hash = i32x4.add(i32x4.mul(hash, i32x4.splat(HASH_ODD)), i32x4.splat(HASH_ADD));
	hash = v128.xor(i32x4.shl(hash, 5), i32x4.shr_u(hash, 27));
	hash = v128.xor(hash, y);
	hash = i32x4.add(i32x4.mul(hash, i32x4.splat(HASH_ODD)), i32x4.splat(HASH_ADD));
	hash = v128.xor(i32x4.shl(hash, 5), i32x4.shr_u(hash, 27));
	hash = v128.xor(hash, z);
	return v128.and(hash, i32x4.splat(HASH_MASK));
}

// ----------------------------------------------------------------------------------
// neighbor search
// ----------------------------------------------------------------------------------

function addNeighbor(p1: i32, p2: i32): void {
	let n = ns + numN * NEIGHBOR_STRIDE;
	i32.store(n, p1, N_P1);
	i32.store(n, p2, N_P2);
	f32.store(n, 0, N_R);
	f32.store(n, 0, N_W);
	f32.store(n, 0, N_NX);
	f32.store(n, 0, N_NY);
	f32.store(n, 0, N_NZ);
	numN++;
}

function registerParticle(particlePointer: i32, cellIndex: i32): void {
	const sizePtr = gridSizes + (cellIndex << B4);
	const size = i32.load(sizePtr);
	const cellPtr = gridData + (cellIndex << CELL_CAPACITY_SHIFT);
	i32.store(cellPtr + size, particlePointer);
	i32.store(sizePtr, size + (1 << B4));
}

const tmpIndices = heap.alloc(CELL_CAPACITY * 32);

export function updateNeighbors(): void {
	// spacial hashing

	// clear grid
	memory.fill(gridSizes, 0, HASH_SIZE << B4);

	// dummy particle that is far away
	const dummyP = (ps + numP * PARTICLE_STRIDE) as i32;
	f32.store(dummyP, 1e9, P_PX);
	f32.store(dummyP, 1e9, P_PY);
	f32.store(dummyP, 1e9, P_PZ);

	for (let i = 0; i < numP; i++) {
		const p = (ps + i * PARTICLE_STRIDE) as i32;
		const x = f32.load(p, P_PX);
		const y = f32.load(p, P_PY);
		const z = f32.load(p, P_PZ);
		const cellX = i32(floor(x * INV_RE));
		const cellY = i32(floor(y * INV_RE));
		const cellZ = i32(floor(z * INV_RE));

		const cx0 = cellX - 1;
		const cx1 = cellX;
		const cx2 = cellX + 1;
		const cy0 = cellY - 1;
		const cy1 = cellY;
		const cy2 = cellY + 1;
		const cz0 = cellZ - 1;
		const cz1 = cellZ;
		const cz2 = cellZ + 1;

		const gdata = i32x4.splat(gridData as i32);
		const gsizes = i32x4.splat(gridSizes as i32);

		// 0 1 2 0 1 2 0 1 2 0 1 2 ...
		const cellX1 = makei32x4(cx0, cx1, cx2, cx0);
		const cellX2 = makei32x4(cx1, cx2, cx0, cx1);
		const cellX3 = makei32x4(cx2, cx0, cx1, cx2);
		const cellX4 = makei32x4(cx0, cx1, cx2, cx0);
		const cellX5 = makei32x4(cx1, cx2, cx0, cx1);
		const cellX6 = makei32x4(cx2, cx0, cx1, cx2);
		const cellX7 = makei32x4(cx0, cx1, cx2, -1);

		// 0 0 0 1 1 1 2 2 2 0 0 0 ...
		const cellY1 = makei32x4(cy0, cy0, cy0, cy1);
		const cellY2 = makei32x4(cy1, cy1, cy2, cy2);
		const cellY3 = makei32x4(cy2, cy0, cy0, cy0);
		const cellY4 = makei32x4(cy1, cy1, cy1, cy2);
		const cellY5 = makei32x4(cy2, cy2, cy0, cy0);
		const cellY6 = makei32x4(cy0, cy1, cy1, cy1);
		const cellY7 = makei32x4(cy2, cy2, cy2, -1);

		// 0 0 0 0 0 0 0 0 0 1 1 1 ...
		const cellZ1 = makei32x4(cz0, cz0, cz0, cz0);
		const cellZ2 = makei32x4(cz0, cz0, cz0, cz0);
		const cellZ3 = makei32x4(cz0, cz1, cz1, cz1);
		const cellZ4 = makei32x4(cz1, cz1, cz1, cz1);
		const cellZ5 = makei32x4(cz1, cz1, cz2, cz2);
		const cellZ6 = makei32x4(cz2, cz2, cz2, cz2);
		const cellZ7 = makei32x4(cz2, cz2, cz2, -1);

		// compute the cell indices
		const cell1 = cellIndexi32x4(cellX1, cellY1, cellZ1);
		const cell2 = cellIndexi32x4(cellX2, cellY2, cellZ2);
		const cell3 = cellIndexi32x4(cellX3, cellY3, cellZ3);
		const cell4 = cellIndexi32x4(cellX4, cellY4, cellZ4);
		const cell5 = cellIndexi32x4(cellX5, cellY5, cellZ5);
		const cell6 = cellIndexi32x4(cellX6, cellY6, cellZ6);
		const cell7 = cellIndexi32x4(cellX7, cellY7, cellZ7);

		// pointers to the cells
		const cellPtr1 = i32x4.add(gdata, i32x4.shl(cell1, CELL_CAPACITY_SHIFT));
		const cellPtr2 = i32x4.add(gdata, i32x4.shl(cell2, CELL_CAPACITY_SHIFT));
		const cellPtr3 = i32x4.add(gdata, i32x4.shl(cell3, CELL_CAPACITY_SHIFT));
		const cellPtr4 = i32x4.add(gdata, i32x4.shl(cell4, CELL_CAPACITY_SHIFT));
		const cellPtr5 = i32x4.add(gdata, i32x4.shl(cell5, CELL_CAPACITY_SHIFT));
		const cellPtr6 = i32x4.add(gdata, i32x4.shl(cell6, CELL_CAPACITY_SHIFT));
		const cellPtr7 = i32x4.add(gdata, i32x4.shl(cell7, CELL_CAPACITY_SHIFT));

		let numIndexBytes = 0;
		{
			let cell: v128;
			let cellPtr: v128;
			cell = cell1;
			cellPtr = cellPtr1;
			{
				const sizePtrs = i32x4.add(gsizes, i32x4.shl(cell, B4));
				const size1 = i32.load(i32x4.extract_lane(sizePtrs, 0));
				const size2 = i32.load(i32x4.extract_lane(sizePtrs, 1));
				const size3 = i32.load(i32x4.extract_lane(sizePtrs, 2));
				const size4 = i32.load(i32x4.extract_lane(sizePtrs, 3));
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 0), size1);
				numIndexBytes += size1;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 1), size2);
				numIndexBytes += size2;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 2), size3);
				numIndexBytes += size3;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 3), size4);
				numIndexBytes += size4;
			}
			cell = cell2;
			cellPtr = cellPtr2;
			{
				const sizePtrs = i32x4.add(gsizes, i32x4.shl(cell, B4));
				const size1 = i32.load(i32x4.extract_lane(sizePtrs, 0));
				const size2 = i32.load(i32x4.extract_lane(sizePtrs, 1));
				const size3 = i32.load(i32x4.extract_lane(sizePtrs, 2));
				const size4 = i32.load(i32x4.extract_lane(sizePtrs, 3));
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 0), size1);
				numIndexBytes += size1;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 1), size2);
				numIndexBytes += size2;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 2), size3);
				numIndexBytes += size3;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 3), size4);
				numIndexBytes += size4;
			}
			cell = cell3;
			cellPtr = cellPtr3;
			{
				const sizePtrs = i32x4.add(gsizes, i32x4.shl(cell, B4));
				const size1 = i32.load(i32x4.extract_lane(sizePtrs, 0));
				const size2 = i32.load(i32x4.extract_lane(sizePtrs, 1));
				const size3 = i32.load(i32x4.extract_lane(sizePtrs, 2));
				const size4 = i32.load(i32x4.extract_lane(sizePtrs, 3));
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 0), size1);
				numIndexBytes += size1;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 1), size2);
				numIndexBytes += size2;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 2), size3);
				numIndexBytes += size3;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 3), size4);
				numIndexBytes += size4;
			}
			cell = cell4;
			cellPtr = cellPtr4;
			{
				const sizePtrs = i32x4.add(gsizes, i32x4.shl(cell, B4));
				const size1 = i32.load(i32x4.extract_lane(sizePtrs, 0));
				const size2 = i32.load(i32x4.extract_lane(sizePtrs, 1));
				const size3 = i32.load(i32x4.extract_lane(sizePtrs, 2));
				const size4 = i32.load(i32x4.extract_lane(sizePtrs, 3));
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 0), size1);
				numIndexBytes += size1;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 1), size2);
				numIndexBytes += size2;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 2), size3);
				numIndexBytes += size3;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 3), size4);
				numIndexBytes += size4;
			}
			cell = cell5;
			cellPtr = cellPtr5;
			{
				const sizePtrs = i32x4.add(gsizes, i32x4.shl(cell, B4));
				const size1 = i32.load(i32x4.extract_lane(sizePtrs, 0));
				const size2 = i32.load(i32x4.extract_lane(sizePtrs, 1));
				const size3 = i32.load(i32x4.extract_lane(sizePtrs, 2));
				const size4 = i32.load(i32x4.extract_lane(sizePtrs, 3));
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 0), size1);
				numIndexBytes += size1;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 1), size2);
				numIndexBytes += size2;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 2), size3);
				numIndexBytes += size3;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 3), size4);
				numIndexBytes += size4;
			}
			cell = cell6;
			cellPtr = cellPtr6;
			{
				const sizePtrs = i32x4.add(gsizes, i32x4.shl(cell, B4));
				const size1 = i32.load(i32x4.extract_lane(sizePtrs, 0));
				const size2 = i32.load(i32x4.extract_lane(sizePtrs, 1));
				const size3 = i32.load(i32x4.extract_lane(sizePtrs, 2));
				const size4 = i32.load(i32x4.extract_lane(sizePtrs, 3));
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 0), size1);
				numIndexBytes += size1;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 1), size2);
				numIndexBytes += size2;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 2), size3);
				numIndexBytes += size3;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 3), size4);
				numIndexBytes += size4;
			}
			cell = cell7;
			cellPtr = cellPtr7;
			{
				const sizePtrs = i32x4.add(gsizes, i32x4.shl(cell, B4));
				const size1 = i32.load(i32x4.extract_lane(sizePtrs, 0));
				const size2 = i32.load(i32x4.extract_lane(sizePtrs, 1));
				const size3 = i32.load(i32x4.extract_lane(sizePtrs, 2));
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 0), size1);
				numIndexBytes += size1;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 1), size2);
				numIndexBytes += size2;
				memory.copy(tmpIndices + numIndexBytes, i32x4.extract_lane(cellPtr, 2), size3);
				numIndexBytes += size3;
			}
		}
		let numIndices = numIndexBytes >> B4;
		while (numIndices % 4 != 0) {
			i32.store(tmpIndices + numIndexBytes, dummyP);
			numIndices++;
			numIndexBytes += 1 << B4;
		}

		const x1 = f32x4.splat(x);
		const y1 = f32x4.splat(y);
		const z1 = f32x4.splat(z);
		for (let k = 0; k < numIndices >> 2; k++) {
			const j = tmpIndices + (k << B16);
			const p21 = i32.load(j, 0);
			const p22 = i32.load(j, 4);
			const p23 = i32.load(j, 8);
			const p24 = i32.load(j, 12);
			const x21 = f32.load(p21, P_PX);
			const x22 = f32.load(p22, P_PX);
			const x23 = f32.load(p23, P_PX);
			const x24 = f32.load(p24, P_PX);
			const x2 = makef32x4(x21, x22, x23, x24);
			const y21 = f32.load(p21, P_PY);
			const y22 = f32.load(p22, P_PY);
			const y23 = f32.load(p23, P_PY);
			const y24 = f32.load(p24, P_PY);
			const y2 = makef32x4(y21, y22, y23, y24);
			const z21 = f32.load(p21, P_PZ);
			const z22 = f32.load(p22, P_PZ);
			const z23 = f32.load(p23, P_PZ);
			const z24 = f32.load(p24, P_PZ);
			const z2 = makef32x4(z21, z22, z23, z24);
			const dx = f32x4.sub(x1, x2);
			const dy = f32x4.sub(y1, y2);
			const dz = f32x4.sub(z1, z2);
			const r2 = f32x4.add(f32x4.add(f32x4.mul(dx, dx), f32x4.mul(dy, dy)), f32x4.mul(dz, dz));
			const lt = f32x4.lt(r2, f32x4.splat(RE2_FAT));
			const hit1 = i32x4.extract_lane(lt, 0) != 0;
			const hit2 = i32x4.extract_lane(lt, 1) != 0;
			const hit3 = i32x4.extract_lane(lt, 2) != 0;
			const hit4 = i32x4.extract_lane(lt, 3) != 0;
			if (hit1) addNeighbor(p, p21);
			if (hit2) addNeighbor(p, p22);
			if (hit3) addNeighbor(p, p23);
			if (hit4) addNeighbor(p, p24);
		}
		registerParticle(p, i32x4.extract_lane(cell4, 1));
	}
}

// ----------------------------------------------------------------------------------
// core sph
// ----------------------------------------------------------------------------------

export function preStep(substeps: i32): void {
	const ss: f32 = f32(substeps);
	const invSS: f32 = 1.0 / ss;
	const invSS2 = invSS * invSS;
	for (let i = 0; i < numP; i++) {
		const p = ps + i * PARTICLE_STRIDE;
		f32.store(p, f32.load(p, P_VX) * invSS, P_VX);
		f32.store(p, f32.load(p, P_VY) * invSS, P_VY);
		f32.store(p, f32.load(p, P_VZ) * invSS, P_VZ);
	}
}

export function postStep(substeps: i32): void {
	const ss: f32 = f32(substeps);
	for (let i = 0; i < numP; i++) {
		const p = ps + i * PARTICLE_STRIDE;
		f32.store(p, f32.load(p, P_VX) * ss, P_VX);
		f32.store(p, f32.load(p, P_VY) * ss, P_VY);
		f32.store(p, f32.load(p, P_VZ) * ss, P_VZ);
	}
}

export function substep(k: f32, k2: f32, gamma: f32, c: f32, n0: f32): void {
	for (let i = 0; i < numP; i++) {
		const p = ps + i * PARTICLE_STRIDE;
		f32.store(p, 0, P_NX);
		f32.store(p, 0, P_NY);
		f32.store(p, 0, P_NZ);
		f32.store(p, 0, P_D);
	}

	const dummyP = (ps + numP * PARTICLE_STRIDE) as i32;
	f32.store(dummyP, 1e9, P_PX);
	f32.store(dummyP, 1e9, P_PY);
	f32.store(dummyP, 1e9, P_PZ);

	// pad neighbors
	while (numN % 4 != 0) {
		const nb = ns + numN * NEIGHBOR_STRIDE;
		i32.store(nb, dummyP, N_P1);
		i32.store(nb, dummyP, N_P2);
		numN++;
	}

	for (let i = 0; i < numN >> 2; i++) {
		const vnb = vns + i * VNEIGHBOR_STRIDE;
		const nb1 = ns + (i << 2) * NEIGHBOR_STRIDE;
		const nb2 = nb1 + NEIGHBOR_STRIDE;
		const nb3 = nb2 + NEIGHBOR_STRIDE;
		const nb4 = nb3 + NEIGHBOR_STRIDE;

		// indices
		const p11 = i32.load(nb1, N_P1);
		const p12 = i32.load(nb2, N_P1);
		const p13 = i32.load(nb3, N_P1);
		const p14 = i32.load(nb4, N_P1);
		const p1 = makei32x4(p11, p12, p13, p14);
		const p21 = i32.load(nb1, N_P2);
		const p22 = i32.load(nb2, N_P2);
		const p23 = i32.load(nb3, N_P2);
		const p24 = i32.load(nb4, N_P2);
		const p2 = makei32x4(p21, p22, p23, p24);

		// positions
		const p1x1 = f32.load(p11, P_PX);
		const p1x2 = f32.load(p12, P_PX);
		const p1x3 = f32.load(p13, P_PX);
		const p1x4 = f32.load(p14, P_PX);
		const p1x = makef32x4(p1x1, p1x2, p1x3, p1x4);
		const p1y1 = f32.load(p11, P_PY);
		const p1y2 = f32.load(p12, P_PY);
		const p1y3 = f32.load(p13, P_PY);
		const p1y4 = f32.load(p14, P_PY);
		const p1y = makef32x4(p1y1, p1y2, p1y3, p1y4);
		const p1z1 = f32.load(p11, P_PZ);
		const p1z2 = f32.load(p12, P_PZ);
		const p1z3 = f32.load(p13, P_PZ);
		const p1z4 = f32.load(p14, P_PZ);
		const p1z = makef32x4(p1z1, p1z2, p1z3, p1z4);
		const p2x1 = f32.load(p21, P_PX);
		const p2x2 = f32.load(p22, P_PX);
		const p2x3 = f32.load(p23, P_PX);
		const p2x4 = f32.load(p24, P_PX);
		const p2x = makef32x4(p2x1, p2x2, p2x3, p2x4);
		const p2y1 = f32.load(p21, P_PY);
		const p2y2 = f32.load(p22, P_PY);
		const p2y3 = f32.load(p23, P_PY);
		const p2y4 = f32.load(p24, P_PY);
		const p2y = makef32x4(p2y1, p2y2, p2y3, p2y4);
		const p2z1 = f32.load(p21, P_PZ);
		const p2z2 = f32.load(p22, P_PZ);
		const p2z3 = f32.load(p23, P_PZ);
		const p2z4 = f32.load(p24, P_PZ);
		const p2z = makef32x4(p2z1, p2z2, p2z3, p2z4);

		// velocities
		const v1x1 = f32.load(p11, P_VX);
		const v1x2 = f32.load(p12, P_VX);
		const v1x3 = f32.load(p13, P_VX);
		const v1x4 = f32.load(p14, P_VX);
		const v1x = makef32x4(v1x1, v1x2, v1x3, v1x4);
		const v1y1 = f32.load(p11, P_VY);
		const v1y2 = f32.load(p12, P_VY);
		const v1y3 = f32.load(p13, P_VY);
		const v1y4 = f32.load(p14, P_VY);
		const v1y = makef32x4(v1y1, v1y2, v1y3, v1y4);
		const v1z1 = f32.load(p11, P_VZ);
		const v1z2 = f32.load(p12, P_VZ);
		const v1z3 = f32.load(p13, P_VZ);
		const v1z4 = f32.load(p14, P_VZ);
		const v1z = makef32x4(v1z1, v1z2, v1z3, v1z4);
		const v2x1 = f32.load(p21, P_VX);
		const v2x2 = f32.load(p22, P_VX);
		const v2x3 = f32.load(p23, P_VX);
		const v2x4 = f32.load(p24, P_VX);
		const v2x = makef32x4(v2x1, v2x2, v2x3, v2x4);
		const v2y1 = f32.load(p21, P_VY);
		const v2y2 = f32.load(p22, P_VY);
		const v2y3 = f32.load(p23, P_VY);
		const v2y4 = f32.load(p24, P_VY);
		const v2y = makef32x4(v2y1, v2y2, v2y3, v2y4);
		const v2z1 = f32.load(p21, P_VZ);
		const v2z2 = f32.load(p22, P_VZ);
		const v2z3 = f32.load(p23, P_VZ);
		const v2z4 = f32.load(p24, P_VZ);
		const v2z = makef32x4(v2z1, v2z2, v2z3, v2z4);
		const rvx = f32x4.sub(v1x, v2x);
		const rvy = f32x4.sub(v1y, v2y);
		const rvz = f32x4.sub(v1z, v2z);

		// normals
		const dx = f32x4.sub(p1x, p2x);
		const dy = f32x4.sub(p1y, p2y);
		const dz = f32x4.sub(p1z, p2z);
		const rsq = f32x4.add(f32x4.add(f32x4.mul(dx, dx), f32x4.mul(dy, dy)), f32x4.mul(dz, dz));
		const r = f32x4.sqrt(rsq);
		const invR = f32x4.div(f32x4.splat(1), f32x4.max(r, f32x4.splat(1e-9)));
		const w = f32x4.max(f32x4.splat(0), f32x4.sub(f32x4.splat(1), f32x4.mul(r, f32x4.splat(INV_RE))));
		const wsq = f32x4.mul(w, w);
		const nx = f32x4.mul(dx, invR);
		const ny = f32x4.mul(dy, invR);
		const nz = f32x4.mul(dz, invR);
		const rvn = f32x4.add(f32x4.add(f32x4.mul(rvx, nx), f32x4.mul(rvy, ny)), f32x4.mul(rvz, nz));
		const wnx = f32x4.mul(w, nx);
		const wny = f32x4.mul(w, ny);
		const wnz = f32x4.mul(w, nz);

		const wnx1 = f32x4.extract_lane(wnx, 0);
		const wnx2 = f32x4.extract_lane(wnx, 1);
		const wnx3 = f32x4.extract_lane(wnx, 2);
		const wnx4 = f32x4.extract_lane(wnx, 3);
		const wny1 = f32x4.extract_lane(wny, 0);
		const wny2 = f32x4.extract_lane(wny, 1);
		const wny3 = f32x4.extract_lane(wny, 2);
		const wny4 = f32x4.extract_lane(wny, 3);
		const wnz1 = f32x4.extract_lane(wnz, 0);
		const wnz2 = f32x4.extract_lane(wnz, 1);
		const wnz3 = f32x4.extract_lane(wnz, 2);
		const wnz4 = f32x4.extract_lane(wnz, 3);
		f32.store(p11, f32.load(p11, P_NX) + wnx1, P_NX);
		f32.store(p12, f32.load(p12, P_NX) + wnx2, P_NX);
		f32.store(p13, f32.load(p13, P_NX) + wnx3, P_NX);
		f32.store(p14, f32.load(p14, P_NX) + wnx4, P_NX);
		f32.store(p11, f32.load(p11, P_NY) + wny1, P_NY);
		f32.store(p12, f32.load(p12, P_NY) + wny2, P_NY);
		f32.store(p13, f32.load(p13, P_NY) + wny3, P_NY);
		f32.store(p14, f32.load(p14, P_NY) + wny4, P_NY);
		f32.store(p11, f32.load(p11, P_NZ) + wnz1, P_NZ);
		f32.store(p12, f32.load(p12, P_NZ) + wnz2, P_NZ);
		f32.store(p13, f32.load(p13, P_NZ) + wnz3, P_NZ);
		f32.store(p14, f32.load(p14, P_NZ) + wnz4, P_NZ);
		f32.store(p21, f32.load(p21, P_NX) - wnx1, P_NX);
		f32.store(p22, f32.load(p22, P_NX) - wnx2, P_NX);
		f32.store(p23, f32.load(p23, P_NX) - wnx3, P_NX);
		f32.store(p24, f32.load(p24, P_NX) - wnx4, P_NX);
		f32.store(p21, f32.load(p21, P_NY) - wny1, P_NY);
		f32.store(p22, f32.load(p22, P_NY) - wny2, P_NY);
		f32.store(p23, f32.load(p23, P_NY) - wny3, P_NY);
		f32.store(p24, f32.load(p24, P_NY) - wny4, P_NY);
		f32.store(p21, f32.load(p21, P_NZ) - wnz1, P_NZ);
		f32.store(p22, f32.load(p22, P_NZ) - wnz2, P_NZ);
		f32.store(p23, f32.load(p23, P_NZ) - wnz3, P_NZ);
		f32.store(p24, f32.load(p24, P_NZ) - wnz4, P_NZ);
		const wsq1 = f32x4.extract_lane(wsq, 0);
		const wsq2 = f32x4.extract_lane(wsq, 1);
		const wsq3 = f32x4.extract_lane(wsq, 2);
		const wsq4 = f32x4.extract_lane(wsq, 3);
		f32.store(p11, f32.load(p11, P_D) + wsq1, P_D);
		f32.store(p12, f32.load(p12, P_D) + wsq2, P_D);
		f32.store(p13, f32.load(p13, P_D) + wsq3, P_D);
		f32.store(p14, f32.load(p14, P_D) + wsq4, P_D);
		f32.store(p21, f32.load(p21, P_D) + wsq1, P_D);
		f32.store(p22, f32.load(p22, P_D) + wsq2, P_D);
		f32.store(p23, f32.load(p23, P_D) + wsq3, P_D);
		f32.store(p24, f32.load(p24, P_D) + wsq4, P_D);

		v128.store(vnb, p1, VN_P1);
		v128.store(vnb, p2, VN_P2);
		v128.store(vnb, w, VN_W);
		v128.store(vnb, wnx, VN_WNX);
		v128.store(vnb, wny, VN_WNY);
		v128.store(vnb, wnz, VN_WNZ);
		v128.store(vnb, rvn, VN_RVN);
	}
	for (let i = 0; i < numP; i++) {
		let p = ps + i * PARTICLE_STRIDE;
		const nx = f32.load(p, P_NX);
		const ny = f32.load(p, P_NY);
		const nz = f32.load(p, P_NZ);
		const d = f32.load(p, P_D);
		f32.store(p, nx * INV_RE_RATIO, P_NX);
		f32.store(p, ny * INV_RE_RATIO, P_NY);
		f32.store(p, nz * INV_RE_RATIO, P_NZ);
		f32.store(p, k * (d - n0), P_P);
	}
	const k2s = f32x4.splat(k2);
	const gammas = f32x4.splat(gamma);
	const cs = f32x4.splat(c);
	for (let i = 0; i < numN >> 2; i++) {
		const vnb = vns + i * VNEIGHBOR_STRIDE;
		const p1 = v128.load(vnb, VN_P1);
		const p11 = i32x4.extract_lane(p1, 0);
		const p12 = i32x4.extract_lane(p1, 1);
		const p13 = i32x4.extract_lane(p1, 2);
		const p14 = i32x4.extract_lane(p1, 3);
		const p2 = v128.load(vnb, VN_P2);
		const p21 = i32x4.extract_lane(p2, 0);
		const p22 = i32x4.extract_lane(p2, 1);
		const p23 = i32x4.extract_lane(p2, 2);
		const p24 = i32x4.extract_lane(p2, 3);
		const pr11 = f32.load(p11, P_P);
		const pr12 = f32.load(p12, P_P);
		const pr13 = f32.load(p13, P_P);
		const pr14 = f32.load(p14, P_P);
		const pr1 = makef32x4(pr11, pr12, pr13, pr14);
		const pr21 = f32.load(p21, P_P);
		const pr22 = f32.load(p22, P_P);
		const pr23 = f32.load(p23, P_P);
		const pr24 = f32.load(p24, P_P);
		const pr2 = makef32x4(pr21, pr22, pr23, pr24);
		const w = v128.load(vnb, VN_W);
		const wnx = v128.load(vnb, VN_WNX);
		const wny = v128.load(vnb, VN_WNY);
		const wnz = v128.load(vnb, VN_WNZ);
		const rvn = v128.load(vnb, VN_RVN);
		const p = f32x4.add(f32x4.add(pr1, pr2), f32x4.mul(f32x4.mul(w, f32x4.mul(w, w)), k2s));
		const n1x1 = f32.load(p11, P_NX);
		const n1x2 = f32.load(p12, P_NX);
		const n1x3 = f32.load(p13, P_NX);
		const n1x4 = f32.load(p14, P_NX);
		const nx1 = makef32x4(n1x1, n1x2, n1x3, n1x4);
		const n1y1 = f32.load(p11, P_NY);
		const n1y2 = f32.load(p12, P_NY);
		const n1y3 = f32.load(p13, P_NY);
		const n1y4 = f32.load(p14, P_NY);
		const ny1 = makef32x4(n1y1, n1y2, n1y3, n1y4);
		const n1z1 = f32.load(p11, P_NZ);
		const n1z2 = f32.load(p12, P_NZ);
		const n1z3 = f32.load(p13, P_NZ);
		const n1z4 = f32.load(p14, P_NZ);
		const nz1 = makef32x4(n1z1, n1z2, n1z3, n1z4);
		const n2x1 = f32.load(p21, P_NX);
		const n2x2 = f32.load(p22, P_NX);
		const n2x3 = f32.load(p23, P_NX);
		const n2x4 = f32.load(p24, P_NX);
		const nx2 = makef32x4(n2x1, n2x2, n2x3, n2x4);
		const n2y1 = f32.load(p21, P_NY);
		const n2y2 = f32.load(p22, P_NY);
		const n2y3 = f32.load(p23, P_NY);
		const n2y4 = f32.load(p24, P_NY);
		const ny2 = makef32x4(n2y1, n2y2, n2y3, n2y4);
		const n2z1 = f32.load(p21, P_NZ);
		const n2z2 = f32.load(p22, P_NZ);
		const n2z3 = f32.load(p23, P_NZ);
		const n2z4 = f32.load(p24, P_NZ);
		const nz2 = makef32x4(n2z1, n2z2, n2z3, n2z4);
		const rnx = f32x4.sub(nx1, nx2);
		const rny = f32x4.sub(ny1, ny2);
		const rnz = f32x4.sub(nz1, nz2);
		const nwCoeff = f32x4.sub(p, f32x4.mul(cs, rvn));
		const rnCoeff = f32x4.mul(w, gammas);
		const fx = f32x4.add(f32x4.mul(wnx, nwCoeff), f32x4.mul(rnx, rnCoeff));
		const fy = f32x4.add(f32x4.mul(wny, nwCoeff), f32x4.mul(rny, rnCoeff));
		const fz = f32x4.add(f32x4.mul(wnz, nwCoeff), f32x4.mul(rnz, rnCoeff));
		const fx1 = f32x4.extract_lane(fx, 0);
		const fx2 = f32x4.extract_lane(fx, 1);
		const fx3 = f32x4.extract_lane(fx, 2);
		const fx4 = f32x4.extract_lane(fx, 3);
		const fy1 = f32x4.extract_lane(fy, 0);
		const fy2 = f32x4.extract_lane(fy, 1);
		const fy3 = f32x4.extract_lane(fy, 2);
		const fy4 = f32x4.extract_lane(fy, 3);
		const fz1 = f32x4.extract_lane(fz, 0);
		const fz2 = f32x4.extract_lane(fz, 1);
		const fz3 = f32x4.extract_lane(fz, 2);
		const fz4 = f32x4.extract_lane(fz, 3);
		f32.store(p11, f32.load(p11, P_VX) + fx1, P_VX);
		f32.store(p12, f32.load(p12, P_VX) + fx2, P_VX);
		f32.store(p13, f32.load(p13, P_VX) + fx3, P_VX);
		f32.store(p14, f32.load(p14, P_VX) + fx4, P_VX);
		f32.store(p11, f32.load(p11, P_VY) + fy1, P_VY);
		f32.store(p12, f32.load(p12, P_VY) + fy2, P_VY);
		f32.store(p13, f32.load(p13, P_VY) + fy3, P_VY);
		f32.store(p14, f32.load(p14, P_VY) + fy4, P_VY);
		f32.store(p11, f32.load(p11, P_VZ) + fz1, P_VZ);
		f32.store(p12, f32.load(p12, P_VZ) + fz2, P_VZ);
		f32.store(p13, f32.load(p13, P_VZ) + fz3, P_VZ);
		f32.store(p14, f32.load(p14, P_VZ) + fz4, P_VZ);
		f32.store(p21, f32.load(p21, P_VX) - fx1, P_VX);
		f32.store(p22, f32.load(p22, P_VX) - fx2, P_VX);
		f32.store(p23, f32.load(p23, P_VX) - fx3, P_VX);
		f32.store(p24, f32.load(p24, P_VX) - fx4, P_VX);
		f32.store(p21, f32.load(p21, P_VY) - fy1, P_VY);
		f32.store(p22, f32.load(p22, P_VY) - fy2, P_VY);
		f32.store(p23, f32.load(p23, P_VY) - fy3, P_VY);
		f32.store(p24, f32.load(p24, P_VY) - fy4, P_VY);
		f32.store(p21, f32.load(p21, P_VZ) - fz1, P_VZ);
		f32.store(p22, f32.load(p22, P_VZ) - fz2, P_VZ);
		f32.store(p23, f32.load(p23, P_VZ) - fz3, P_VZ);
		f32.store(p24, f32.load(p24, P_VZ) - fz4, P_VZ);
	}
}

// ----------------------------------------------------------------------------------
// mesh reconstruction
// ----------------------------------------------------------------------------------

const MESH_RES_SHIFT: i32 = 6;
const MESH_RES_SHIFT2: i32 = MESH_RES_SHIFT * 2;
const MESH_RES_SHIFT3: i32 = MESH_RES_SHIFT * 3;
const MESH_RES: i32 = 1 << MESH_RES_SHIFT;
const MESH_RES_MASK: i32 = MESH_RES - 1;
const MESH_RES2: i32 = MESH_RES * MESH_RES;
const MESH_RES3: i32 = MESH_RES * MESH_RES * MESH_RES;
const MESH_GRID_SIZE: f32 = INTERVAL;
const INV_MESH_GRID_SIZE: f32 = 1 / MESH_GRID_SIZE;

// repeat of
//     numTris, edge11, edge12, edge13,
//     edge21, edge22, edge23, edge31,
//     edge32, edge33, edge41, edge42,
//     edge43, edge51, edge52, edge53
const table = heap.alloc((256 * 4) << B4);

// density field
const meshWeights = heap.alloc(MESH_RES3 << B4);
// true if marked
const cellVisited = heap.alloc(MESH_RES3);
// ignore unmarked cells
const markedCells = heap.alloc(MESH_RES3 << B4);
let numMarkedCells: i32;
// edge index -> vertex index, -1 means none
const edgeToVertex = heap.alloc((MESH_RES3 * 3) << B4);

const MAX_TRIS = 65536;
const MAX_VERTS = 65536;

const VERTEX_STRIDE = 10 << B4;
const V_X = 0 << B4; // position
const V_Y = 1 << B4;
const V_Z = 2 << B4;
const V_X2 = 3 << B4; // temporary
const V_Y2 = 4 << B4;
const V_Z2 = 5 << B4;
const V_NX = 6 << B4; // normal
const V_NY = 7 << B4;
const V_NZ = 8 << B4;
const V_WEIGHT = 9 << B4;
const verts = heap.alloc(MAX_VERTS * VERTEX_STRIDE);

const FINAL_VERTEX_STRIDE = 6 << B4;
const FV_X = 0 << B4; // position
const FV_Y = 1 << B4;
const FV_Z = 2 << B4;
const FV_NX = 3 << B4; // normal
const FV_NY = 4 << B4;
const FV_NZ = 5 << B4;
const fverts = heap.alloc(MAX_VERTS * FINAL_VERTEX_STRIDE);

let numVerts: i32 = 0;
let numTris: i32 = 0;

const TRI_STRIDE = 3 << B4;
const T_V1 = 0 << B4;
const T_V2 = 1 << B4;
const T_V3 = 2 << B4;
const tris = heap.alloc(MAX_TRIS * TRI_STRIDE);

export function numMeshVerts(): i32 {
	return numVerts;
}

export function meshVertices(): usize {
	return fverts;
}

export function numMeshTris(): i32 {
	return numTris;
}

export function meshTris(): usize {
	return tris;
}

export function mcTable(): usize {
	return table;
}

export function cellWeights(): usize {
	return meshWeights;
}

function f32x4pow2(x: v128): v128 {
	return f32x4.mul(x, x);
}

const debugData = heap.alloc(1024);
export function debug(): usize {
	return debugData;
}

// local vars in updateMesh
const wxs = heap.alloc(3 << B16);
const wys = heap.alloc(3 << B16);
const wzs = heap.alloc(3 << B16);

function makeTri(threshold: f32, x: v128, y: v128, z: v128, e: v128): void {
	const x1 = i32x4.add(x, v128.and(i32x4.shr_u(e, 5), i32x4.splat(1)));
	const y1 = i32x4.add(y, v128.and(i32x4.shr_u(e, 4), i32x4.splat(1)));
	const z1 = i32x4.add(z, v128.and(i32x4.shr_u(e, 3), i32x4.splat(1)));
	const x2 = i32x4.add(x, v128.and(i32x4.shr_u(e, 2), i32x4.splat(1)));
	const y2 = i32x4.add(y, v128.and(i32x4.shr_u(e, 1), i32x4.splat(1)));
	const z2 = i32x4.add(z, v128.and(e, i32x4.splat(1)));
	const dir = v128.or(v128.and(i32x4.ne(y1, y2), i32x4.splat(1)), v128.and(i32x4.ne(z1, z2), i32x4.splat(2)));
	const idx1 = v128.or(i32x4.shl(x1, MESH_RES_SHIFT2), v128.or(i32x4.shl(y1, MESH_RES_SHIFT), z1));
	const idx2 = v128.or(i32x4.shl(x2, MESH_RES_SHIFT2), v128.or(i32x4.shl(y2, MESH_RES_SHIFT), z2));
	const edgeIndex = i32x4.shl(v128.or(i32x4.shl(dir, MESH_RES_SHIFT3), idx1), B4);
	const ptr = i32x4.add(i32x4.splat(edgeToVertex as i32), edgeIndex);
	const widx1 = i32x4.add(i32x4.splat(meshWeights as i32), i32x4.shl(idx1, B4));
	const widx2 = i32x4.add(i32x4.splat(meshWeights as i32), i32x4.shl(idx2, B4));
	const ptr1 = i32x4.extract_lane(ptr, 0);
	const ptr2 = i32x4.extract_lane(ptr, 1);
	const ptr3 = i32x4.extract_lane(ptr, 2);
	const v11 = f32.load(i32x4.extract_lane(widx1, 0));
	const v12 = f32.load(i32x4.extract_lane(widx1, 1));
	const v13 = f32.load(i32x4.extract_lane(widx1, 2));
	const v1 = makef32x4(v11, v12, v13, 0);
	const v21 = f32.load(i32x4.extract_lane(widx2, 0));
	const v22 = f32.load(i32x4.extract_lane(widx2, 1));
	const v23 = f32.load(i32x4.extract_lane(widx2, 2));
	const v2 = makef32x4(v21, v22, v23, 0);
	const t = f32x4.div(f32x4.sub(f32x4.splat(threshold), v1), f32x4.sub(v2, v1));
	const shift = f32x4.splat(((MESH_RES - 1) * 0.5) as f32);
	const scale = f32x4.splat(MESH_GRID_SIZE);
	const fx1 = f32x4.mul(f32x4.sub(f32x4.convert_i32x4_s(x1), shift), scale);
	const fy1 = f32x4.mul(f32x4.sub(f32x4.convert_i32x4_s(y1), shift), scale);
	const fz1 = f32x4.mul(f32x4.sub(f32x4.convert_i32x4_s(z1), shift), scale);
	const fx2 = f32x4.mul(f32x4.sub(f32x4.convert_i32x4_s(x2), shift), scale);
	const fy2 = f32x4.mul(f32x4.sub(f32x4.convert_i32x4_s(y2), shift), scale);
	const fz2 = f32x4.mul(f32x4.sub(f32x4.convert_i32x4_s(z2), shift), scale);
	const px = f32x4.add(f32x4.mul(f32x4.sub(fx2, fx1), t), fx1);
	const py = f32x4.add(f32x4.mul(f32x4.sub(fy2, fy1), t), fy1);
	const pz = f32x4.add(f32x4.mul(f32x4.sub(fz2, fz1), t), fz1);
	if (i32.load(ptr1) == -1) {
		const v = verts + numVerts * VERTEX_STRIDE;
		f32.store(v, f32x4.extract_lane(px, 0), V_X);
		f32.store(v, f32x4.extract_lane(py, 0), V_Y);
		f32.store(v, f32x4.extract_lane(pz, 0), V_Z);
		f32.store(v, 0, V_NX);
		f32.store(v, 0, V_NY);
		f32.store(v, 0, V_NZ);
		i32.store(ptr1, numVerts++);
	}
	if (i32.load(ptr2) == -1) {
		const v = verts + numVerts * VERTEX_STRIDE;
		f32.store(v, f32x4.extract_lane(px, 1), V_X);
		f32.store(v, f32x4.extract_lane(py, 1), V_Y);
		f32.store(v, f32x4.extract_lane(pz, 1), V_Z);
		f32.store(v, 0, V_NX);
		f32.store(v, 0, V_NY);
		f32.store(v, 0, V_NZ);
		i32.store(ptr2, numVerts++);
	}
	if (i32.load(ptr3) == -1) {
		const v = verts + numVerts * VERTEX_STRIDE;
		f32.store(v, f32x4.extract_lane(px, 2), V_X);
		f32.store(v, f32x4.extract_lane(py, 2), V_Y);
		f32.store(v, f32x4.extract_lane(pz, 2), V_Z);
		f32.store(v, 0, V_NX);
		f32.store(v, 0, V_NY);
		f32.store(v, 0, V_NZ);
		i32.store(ptr3, numVerts++);
	}
	const tri = tris + numTris * TRI_STRIDE;
	i32.store(tri, i32.load(ptr1), T_V1);
	i32.store(tri, i32.load(ptr2), T_V2);
	i32.store(tri, i32.load(ptr3), T_V3);
	numTris++;
}

export function updateMesh(threshold: f32, n0: f32, updateDensity: bool): void {
	if (updateDensity) {
		for (let i = 0; i < numP; i++) {
			const p = ps + i * PARTICLE_STRIDE;
			f32.store(p, 0, P_D);
		}

		const dummyP = (ps + numP * PARTICLE_STRIDE) as i32;

		// pad neighbors
		while (numN % 4 != 0) {
			const nb = ns + numN * NEIGHBOR_STRIDE;
			i32.store(nb, dummyP, N_P1);
			i32.store(nb, dummyP, N_P2);
			numN++;
		}

		for (let i = 0; i < numN >> 2; i++) {
			const nb1 = ns + (i << 2) * NEIGHBOR_STRIDE;
			const nb2 = nb1 + NEIGHBOR_STRIDE;
			const nb3 = nb2 + NEIGHBOR_STRIDE;
			const nb4 = nb3 + NEIGHBOR_STRIDE;

			// indices
			const p11 = i32.load(nb1, N_P1);
			const p12 = i32.load(nb2, N_P1);
			const p13 = i32.load(nb3, N_P1);
			const p14 = i32.load(nb4, N_P1);
			const p21 = i32.load(nb1, N_P2);
			const p22 = i32.load(nb2, N_P2);
			const p23 = i32.load(nb3, N_P2);
			const p24 = i32.load(nb4, N_P2);

			// positions
			const p1x1 = f32.load(p11, P_PX);
			const p1x2 = f32.load(p12, P_PX);
			const p1x3 = f32.load(p13, P_PX);
			const p1x4 = f32.load(p14, P_PX);
			const p1x = makef32x4(p1x1, p1x2, p1x3, p1x4);
			const p1y1 = f32.load(p11, P_PY);
			const p1y2 = f32.load(p12, P_PY);
			const p1y3 = f32.load(p13, P_PY);
			const p1y4 = f32.load(p14, P_PY);
			const p1y = makef32x4(p1y1, p1y2, p1y3, p1y4);
			const p1z1 = f32.load(p11, P_PZ);
			const p1z2 = f32.load(p12, P_PZ);
			const p1z3 = f32.load(p13, P_PZ);
			const p1z4 = f32.load(p14, P_PZ);
			const p1z = makef32x4(p1z1, p1z2, p1z3, p1z4);
			const p2x1 = f32.load(p21, P_PX);
			const p2x2 = f32.load(p22, P_PX);
			const p2x3 = f32.load(p23, P_PX);
			const p2x4 = f32.load(p24, P_PX);
			const p2x = makef32x4(p2x1, p2x2, p2x3, p2x4);
			const p2y1 = f32.load(p21, P_PY);
			const p2y2 = f32.load(p22, P_PY);
			const p2y3 = f32.load(p23, P_PY);
			const p2y4 = f32.load(p24, P_PY);
			const p2y = makef32x4(p2y1, p2y2, p2y3, p2y4);
			const p2z1 = f32.load(p21, P_PZ);
			const p2z2 = f32.load(p22, P_PZ);
			const p2z3 = f32.load(p23, P_PZ);
			const p2z4 = f32.load(p24, P_PZ);
			const p2z = makef32x4(p2z1, p2z2, p2z3, p2z4);

			// normals
			const dx = f32x4.sub(p1x, p2x);
			const dy = f32x4.sub(p1y, p2y);
			const dz = f32x4.sub(p1z, p2z);
			const rsq = f32x4.add(f32x4.add(f32x4.mul(dx, dx), f32x4.mul(dy, dy)), f32x4.mul(dz, dz));
			const r = f32x4.sqrt(rsq);
			const w = f32x4.max(f32x4.splat(0), f32x4.sub(f32x4.splat(1), f32x4.mul(r, f32x4.splat(INV_RE))));
			const wsq = f32x4.mul(w, w);
			const wsq1 = f32x4.extract_lane(wsq, 0);
			const wsq2 = f32x4.extract_lane(wsq, 1);
			const wsq3 = f32x4.extract_lane(wsq, 2);
			const wsq4 = f32x4.extract_lane(wsq, 3);
			f32.store(p11, f32.load(p11, P_D) + wsq1, P_D);
			f32.store(p12, f32.load(p12, P_D) + wsq2, P_D);
			f32.store(p13, f32.load(p13, P_D) + wsq3, P_D);
			f32.store(p14, f32.load(p14, P_D) + wsq4, P_D);
			f32.store(p21, f32.load(p21, P_D) + wsq1, P_D);
			f32.store(p22, f32.load(p22, P_D) + wsq2, P_D);
			f32.store(p23, f32.load(p23, P_D) + wsq3, P_D);
			f32.store(p24, f32.load(p24, P_D) + wsq4, P_D);
		}
	}

	const invN0s = f32x4.splat(1 / n0);
	memory.fill(meshWeights, 0, MESH_RES3 << B4);
	memory.fill(cellVisited, 0, MESH_RES3);
	memory.fill(edgeToVertex, 0xff, (MESH_RES3 * 3) << B4);
	numMarkedCells = 0;

	for (let i = 0; i < (numP + 3) >> 2; i++) {
		const p1 = ps + (i << 2) * PARTICLE_STRIDE;
		const p2 = p1 + PARTICLE_STRIDE;
		const p3 = p2 + PARTICLE_STRIDE;
		const p4 = p3 + PARTICLE_STRIDE;
		const px1 = f32.load(p1, P_PX);
		const px2 = f32.load(p2, P_PX);
		const px3 = f32.load(p3, P_PX);
		const px4 = f32.load(p4, P_PX);
		const px = makef32x4(px1, px2, px3, px4);
		const py1 = f32.load(p1, P_PY);
		const py2 = f32.load(p2, P_PY);
		const py3 = f32.load(p3, P_PY);
		const py4 = f32.load(p4, P_PY);
		const py = makef32x4(py1, py2, py3, py4);
		const pz1 = f32.load(p1, P_PZ);
		const pz2 = f32.load(p2, P_PZ);
		const pz3 = f32.load(p3, P_PZ);
		const pz4 = f32.load(p4, P_PZ);
		const pz = makef32x4(pz1, pz2, pz3, pz4);
		const scale = f32x4.splat(INV_MESH_GRID_SIZE);
		const shift = f32x4.splat((MESH_RES >> 1) as f32);
		const gx = f32x4.add(f32x4.mul(px, scale), shift);
		const gy = f32x4.add(f32x4.mul(py, scale), shift);
		const gz = f32x4.add(f32x4.mul(pz, scale), shift);
		const fgx = f32x4.floor(gx);
		const fgy = f32x4.floor(gy);
		const fgz = f32x4.floor(gz);
		const igx = i32x4.trunc_sat_f32x4_s(fgx);
		const igy = i32x4.trunc_sat_f32x4_s(fgy);
		const igz = i32x4.trunc_sat_f32x4_s(fgz);
		// cell -> particle
		const fx = f32x4.sub(f32x4.sub(gx, fgx), f32x4.splat(0.5));
		const fy = f32x4.sub(f32x4.sub(gy, fgy), f32x4.splat(0.5));
		const fz = f32x4.sub(f32x4.sub(gz, fgz), f32x4.splat(0.5));

		const wx0 = f32x4.mul(f32x4.splat(0.5), f32x4pow2(f32x4.sub(f32x4.splat(0.5), fx)));
		const wx1 = f32x4.sub(f32x4.splat(0.75), f32x4.mul(fx, fx));
		const wx2 = f32x4.mul(f32x4.splat(0.5), f32x4pow2(f32x4.add(f32x4.splat(0.5), fx)));
		const wy0 = f32x4.mul(f32x4.splat(0.5), f32x4pow2(f32x4.sub(f32x4.splat(0.5), fy)));
		const wy1 = f32x4.sub(f32x4.splat(0.75), f32x4.mul(fy, fy));
		const wy2 = f32x4.mul(f32x4.splat(0.5), f32x4pow2(f32x4.add(f32x4.splat(0.5), fy)));
		const wz0 = f32x4.mul(f32x4.splat(0.5), f32x4pow2(f32x4.sub(f32x4.splat(0.5), fz)));
		const wz1 = f32x4.sub(f32x4.splat(0.75), f32x4.mul(fz, fz));
		const wz2 = f32x4.mul(f32x4.splat(0.5), f32x4pow2(f32x4.add(f32x4.splat(0.5), fz)));
		const density1 = f32.load(p1, P_D);
		const density2 = f32.load(p2, P_D);
		const density3 = f32.load(p3, P_D);
		const density4 = f32.load(p4, P_D);
		const density = makef32x4(density1, density2, density3, density4);
		const w = f32x4.add(
			f32x4.splat(1),
			f32x4.max(f32x4.splat(0), f32x4.sub(f32x4.splat(1), f32x4.mul(density, invN0s)))
		);
		v128.store(wxs, f32x4.mul(wx0, w), 0 << B16);
		v128.store(wxs, f32x4.mul(wx1, w), 1 << B16);
		v128.store(wxs, f32x4.mul(wx2, w), 2 << B16);
		v128.store(wys, f32x4.mul(wy0, w), 0 << B16);
		v128.store(wys, f32x4.mul(wy1, w), 1 << B16);
		v128.store(wys, f32x4.mul(wy2, w), 2 << B16);
		v128.store(wzs, f32x4.mul(wz0, w), 0 << B16);
		v128.store(wzs, f32x4.mul(wz1, w), 1 << B16);
		v128.store(wzs, f32x4.mul(wz2, w), 2 << B16);
		for (let di = -1; di < 2; di++) {
			for (let dj = -1; dj < 2; dj++) {
				for (let dk = -1; dk < 2; dk++) {
					const x = v128.and(i32x4.add(igx, i32x4.splat(di)), i32x4.splat(MESH_RES_MASK));
					const y = v128.and(i32x4.add(igy, i32x4.splat(dj)), i32x4.splat(MESH_RES_MASK));
					const z = v128.and(i32x4.add(igz, i32x4.splat(dk)), i32x4.splat(MESH_RES_MASK));
					const idx = v128.or(i32x4.shl(x, MESH_RES_SHIFT2), v128.or(i32x4.shl(y, MESH_RES_SHIFT), z));
					const wx = v128.load(wxs + ((di + 1) << B16));
					const wy = v128.load(wys + ((dj + 1) << B16));
					const wz = v128.load(wzs + ((dk + 1) << B16));
					const wxyz = f32x4.mul(f32x4.mul(wx, wy), wz);
					const wptr = i32x4.add(i32x4.splat(meshWeights as i32), i32x4.shl(idx, B4));
					const vptr = i32x4.add(i32x4.splat(cellVisited as i32), idx);
					const wptr1 = i32x4.extract_lane(wptr, 0);
					const vptr1 = i32x4.extract_lane(vptr, 0);
					f32.store(wptr1, f32.load(wptr1) + f32x4.extract_lane(wxyz, 0));
					if (f32.load(wptr1) >= threshold && !i32.load8_s(vptr1)) {
						i32.store8(vptr1, 1);
						i32.store(markedCells + (numMarkedCells++ << B4), i32x4.extract_lane(idx, 0));
					}
					if ((i << 2) + 1 >= numP) continue;
					const wptr2 = i32x4.extract_lane(wptr, 1);
					const vptr2 = i32x4.extract_lane(vptr, 1);
					f32.store(wptr2, f32.load(wptr2) + f32x4.extract_lane(wxyz, 1));
					if (f32.load(wptr2) >= threshold && !i32.load8_s(vptr2)) {
						i32.store8(vptr2, 1);
						i32.store(markedCells + (numMarkedCells++ << B4), i32x4.extract_lane(idx, 1));
					}
					if ((i << 2) + 2 >= numP) continue;
					const wptr3 = i32x4.extract_lane(wptr, 2);
					const vptr3 = i32x4.extract_lane(vptr, 2);
					f32.store(wptr3, f32.load(wptr3) + f32x4.extract_lane(wxyz, 2));
					if (f32.load(wptr3) >= threshold && !i32.load8_s(vptr3)) {
						i32.store8(vptr3, 1);
						i32.store(markedCells + (numMarkedCells++ << B4), i32x4.extract_lane(idx, 2));
					}
					if ((i << 2) + 3 >= numP) continue;
					const wptr4 = i32x4.extract_lane(wptr, 3);
					const vptr4 = i32x4.extract_lane(vptr, 3);
					f32.store(wptr4, f32.load(wptr4) + f32x4.extract_lane(wxyz, 3));
					if (f32.load(wptr4) >= threshold && !i32.load8_s(vptr4)) {
						i32.store8(vptr4, 1);
						i32.store(markedCells + (numMarkedCells++ << B4), i32x4.extract_lane(idx, 3));
					}
				}
			}
		}
	}
	{
		const size = numMarkedCells;
		for (let ii = 0; ii < size; ii++) {
			const idx = i32.load(markedCells + (ii << B4));
			const x = (idx >> MESH_RES_SHIFT2) & MESH_RES_MASK;
			const y = (idx >> MESH_RES_SHIFT) & MESH_RES_MASK;
			const z = idx & MESH_RES_MASK;
			const x0 = ((x - 1) & MESH_RES_MASK) << MESH_RES_SHIFT2;
			const y0 = ((y - 1) & MESH_RES_MASK) << MESH_RES_SHIFT;
			const z0 = (z - 1) & MESH_RES_MASK;
			const x1 = x << MESH_RES_SHIFT2;
			const y1 = y << MESH_RES_SHIFT;
			const z1 = z;
			const i000 = x0 | y0 | z0;
			const i001 = x0 | y0 | z1;
			const i010 = x0 | y1 | z0;
			const i011 = x0 | y1 | z1;
			const i100 = x1 | y0 | z0;
			const i101 = x1 | y0 | z1;
			const i110 = x1 | y1 | z0;
			const i111 = x1 | y1 | z1;
			if (!i32.load8_s(cellVisited + i000)) {
				i32.store8(cellVisited + i000, 1);
				i32.store(markedCells + (numMarkedCells++ << B4), i000);
			}
			if (!i32.load8_s(cellVisited + i001)) {
				i32.store8(cellVisited + i001, 1);
				i32.store(markedCells + (numMarkedCells++ << B4), i001);
			}
			if (!i32.load8_s(cellVisited + i010)) {
				i32.store8(cellVisited + i010, 1);
				i32.store(markedCells + (numMarkedCells++ << B4), i010);
			}
			if (!i32.load8_s(cellVisited + i011)) {
				i32.store8(cellVisited + i011, 1);
				i32.store(markedCells + (numMarkedCells++ << B4), i011);
			}
			if (!i32.load8_s(cellVisited + i100)) {
				i32.store8(cellVisited + i100, 1);
				i32.store(markedCells + (numMarkedCells++ << B4), i100);
			}
			if (!i32.load8_s(cellVisited + i101)) {
				i32.store8(cellVisited + i101, 1);
				i32.store(markedCells + (numMarkedCells++ << B4), i101);
			}
			if (!i32.load8_s(cellVisited + i110)) {
				i32.store8(cellVisited + i110, 1);
				i32.store(markedCells + (numMarkedCells++ << B4), i110);
			}
			if (!i32.load8_s(cellVisited + i111)) {
				i32.store8(cellVisited + i111, 1);
				i32.store(markedCells + (numMarkedCells++ << B4), i111);
			}
		}
	}
	numVerts = 0;
	numTris = 0;
	for (let ii = 0; ii < numMarkedCells; ii++) {
		const idx = i32.load(markedCells + (ii << B4));
		const x = (idx >> MESH_RES_SHIFT2) & MESH_RES_MASK;
		const y = (idx >> MESH_RES_SHIFT) & MESH_RES_MASK;
		const z = idx & MESH_RES_MASK;
		if (x == MESH_RES_MASK || y == MESH_RES_MASK || z == MESH_RES_MASK) continue;
		const x1 = (x + 1) & MESH_RES_MASK;
		const y1 = (y + 1) & MESH_RES_MASK;
		const z1 = (z + 1) & MESH_RES_MASK;
		const ix0 = x << MESH_RES_SHIFT2;
		const ix1 = x1 << MESH_RES_SHIFT2;
		const iy0 = y << MESH_RES_SHIFT;
		const iy1 = y1 << MESH_RES_SHIFT;
		const iz0 = z;
		const iz1 = z1;
		let bits = 0;
		if (f32.load(meshWeights + ((ix0 | iy0 | iz0) << B4)) < threshold) bits |= 1 << 0;
		if (f32.load(meshWeights + ((ix0 | iy0 | iz1) << B4)) < threshold) bits |= 1 << 1;
		if (f32.load(meshWeights + ((ix0 | iy1 | iz0) << B4)) < threshold) bits |= 1 << 2;
		if (f32.load(meshWeights + ((ix0 | iy1 | iz1) << B4)) < threshold) bits |= 1 << 3;
		if (f32.load(meshWeights + ((ix1 | iy0 | iz0) << B4)) < threshold) bits |= 1 << 4;
		if (f32.load(meshWeights + ((ix1 | iy0 | iz1) << B4)) < threshold) bits |= 1 << 5;
		if (f32.load(meshWeights + ((ix1 | iy1 | iz0) << B4)) < threshold) bits |= 1 << 6;
		if (f32.load(meshWeights + ((ix1 | iy1 | iz1) << B4)) < threshold) bits |= 1 << 7;
		if (bits == 0 || bits == 0xff) continue;
		let tptr = table + ((bits * 4) << B4);
		const numTris = i32.load8_u(tptr++);
		const xs = i32x4.splat(x);
		const ys = i32x4.splat(y);
		const zs = i32x4.splat(z);
		do {
			makeTri(threshold, xs, ys, zs, makei32x4(i32.load8_u(tptr++), i32.load8_u(tptr++), i32.load8_u(tptr++), 0));
			if (numTris == 1) break;
			makeTri(threshold, xs, ys, zs, makei32x4(i32.load8_u(tptr++), i32.load8_u(tptr++), i32.load8_u(tptr++), 0));
			if (numTris == 2) break;
			makeTri(threshold, xs, ys, zs, makei32x4(i32.load8_u(tptr++), i32.load8_u(tptr++), i32.load8_u(tptr++), 0));
			if (numTris == 3) break;
			makeTri(threshold, xs, ys, zs, makei32x4(i32.load8_u(tptr++), i32.load8_u(tptr++), i32.load8_u(tptr++), 0));
			if (numTris == 4) break;
			makeTri(threshold, xs, ys, zs, makei32x4(i32.load8_u(tptr++), i32.load8_u(tptr++), i32.load8_u(tptr++), 0));
		} while (false);
	}

	for (let i = 0; i < numVerts; i++) {
		const v = verts + i * VERTEX_STRIDE;
		f32.store(v, 0, V_X2);
		f32.store(v, 0, V_Y2);
		f32.store(v, 0, V_Z2);
		f32.store(v, 0, V_WEIGHT);
	}
	// pad tris
	const dummyV = numVerts;
	const numOrigTris = numTris;
	while (numTris % 4 != 0) {
		const t = tris + ((numTris * 3) << B4);
		i32.store(t, dummyV, 0 << B4);
		i32.store(t, dummyV, 1 << B4);
		i32.store(t, dummyV, 2 << B4);
		numTris++;
	}
	// pass1
	for (let i = 0; i < numTris >> 2; i++) {
		const t1 = tris + (i << 2) * TRI_STRIDE;
		const t2 = t1 + TRI_STRIDE;
		const t3 = t2 + TRI_STRIDE;
		const t4 = t3 + TRI_STRIDE;
		const v11 = verts + i32.load(t1, T_V1) * VERTEX_STRIDE;
		const v12 = verts + i32.load(t2, T_V1) * VERTEX_STRIDE;
		const v13 = verts + i32.load(t3, T_V1) * VERTEX_STRIDE;
		const v14 = verts + i32.load(t4, T_V1) * VERTEX_STRIDE;
		const v21 = verts + i32.load(t1, T_V2) * VERTEX_STRIDE;
		const v22 = verts + i32.load(t2, T_V2) * VERTEX_STRIDE;
		const v23 = verts + i32.load(t3, T_V2) * VERTEX_STRIDE;
		const v24 = verts + i32.load(t4, T_V2) * VERTEX_STRIDE;
		const v31 = verts + i32.load(t1, T_V3) * VERTEX_STRIDE;
		const v32 = verts + i32.load(t2, T_V3) * VERTEX_STRIDE;
		const v33 = verts + i32.load(t3, T_V3) * VERTEX_STRIDE;
		const v34 = verts + i32.load(t4, T_V3) * VERTEX_STRIDE;
		const x11 = f32.load(v11, V_X);
		const x12 = f32.load(v12, V_X);
		const x13 = f32.load(v13, V_X);
		const x14 = f32.load(v14, V_X);
		const x1 = makef32x4(x11, x12, x13, x14);
		const y11 = f32.load(v11, V_Y);
		const y12 = f32.load(v12, V_Y);
		const y13 = f32.load(v13, V_Y);
		const y14 = f32.load(v14, V_Y);
		const y1 = makef32x4(y11, y12, y13, y14);
		const z11 = f32.load(v11, V_Z);
		const z12 = f32.load(v12, V_Z);
		const z13 = f32.load(v13, V_Z);
		const z14 = f32.load(v14, V_Z);
		const z1 = makef32x4(z11, z12, z13, z14);
		const x21 = f32.load(v21, V_X);
		const x22 = f32.load(v22, V_X);
		const x23 = f32.load(v23, V_X);
		const x24 = f32.load(v24, V_X);
		const x2 = makef32x4(x21, x22, x23, x24);
		const y21 = f32.load(v21, V_Y);
		const y22 = f32.load(v22, V_Y);
		const y23 = f32.load(v23, V_Y);
		const y24 = f32.load(v24, V_Y);
		const y2 = makef32x4(y21, y22, y23, y24);
		const z21 = f32.load(v21, V_Z);
		const z22 = f32.load(v22, V_Z);
		const z23 = f32.load(v23, V_Z);
		const z24 = f32.load(v24, V_Z);
		const z2 = makef32x4(z21, z22, z23, z24);
		const x31 = f32.load(v31, V_X);
		const x32 = f32.load(v32, V_X);
		const x33 = f32.load(v33, V_X);
		const x34 = f32.load(v34, V_X);
		const x3 = makef32x4(x31, x32, x33, x34);
		const y31 = f32.load(v31, V_Y);
		const y32 = f32.load(v32, V_Y);
		const y33 = f32.load(v33, V_Y);
		const y34 = f32.load(v34, V_Y);
		const y3 = makef32x4(y31, y32, y33, y34);
		const z31 = f32.load(v31, V_Z);
		const z32 = f32.load(v32, V_Z);
		const z33 = f32.load(v33, V_Z);
		const z34 = f32.load(v34, V_Z);
		const z3 = makef32x4(z31, z32, z33, z34);
		const v12x = f32x4.sub(x2, x1);
		const v12y = f32x4.sub(y2, y1);
		const v12z = f32x4.sub(z2, z1);
		const v13x = f32x4.sub(x3, x1);
		const v13y = f32x4.sub(y3, y1);
		const v13z = f32x4.sub(z3, z1);
		// v12 cross v13
		const cx = f32x4.sub(f32x4.mul(v12y, v13z), f32x4.mul(v12z, v13y));
		const cy = f32x4.sub(f32x4.mul(v12z, v13x), f32x4.mul(v12x, v13z));
		const cz = f32x4.sub(f32x4.mul(v12x, v13y), f32x4.mul(v12y, v13x));
		const area = f32x4.sqrt(f32x4.add(f32x4.add(f32x4pow2(cx), f32x4pow2(cy)), f32x4pow2(cz)));
		const area1 = f32x4.extract_lane(area, 0);
		const area2 = f32x4.extract_lane(area, 1);
		const area3 = f32x4.extract_lane(area, 2);
		const area4 = f32x4.extract_lane(area, 3);
		f32.store(v11, f32.load(v11, V_WEIGHT) + area1, V_WEIGHT);
		f32.store(v12, f32.load(v12, V_WEIGHT) + area2, V_WEIGHT);
		f32.store(v13, f32.load(v13, V_WEIGHT) + area3, V_WEIGHT);
		f32.store(v14, f32.load(v14, V_WEIGHT) + area4, V_WEIGHT);
		f32.store(v21, f32.load(v21, V_WEIGHT) + area1, V_WEIGHT);
		f32.store(v22, f32.load(v22, V_WEIGHT) + area2, V_WEIGHT);
		f32.store(v23, f32.load(v23, V_WEIGHT) + area3, V_WEIGHT);
		f32.store(v24, f32.load(v24, V_WEIGHT) + area4, V_WEIGHT);
		f32.store(v31, f32.load(v31, V_WEIGHT) + area1, V_WEIGHT);
		f32.store(v32, f32.load(v32, V_WEIGHT) + area2, V_WEIGHT);
		f32.store(v33, f32.load(v33, V_WEIGHT) + area3, V_WEIGHT);
		f32.store(v34, f32.load(v34, V_WEIGHT) + area4, V_WEIGHT);
		const harea = f32x4.mul(area, f32x4.splat(0.5));
		const w23x = f32x4.mul(f32x4.add(x2, x3), harea);
		const w23y = f32x4.mul(f32x4.add(y2, y3), harea);
		const w23z = f32x4.mul(f32x4.add(z2, z3), harea);
		const w31x = f32x4.mul(f32x4.add(x3, x1), harea);
		const w31y = f32x4.mul(f32x4.add(y3, y1), harea);
		const w31z = f32x4.mul(f32x4.add(z3, z1), harea);
		const w12x = f32x4.mul(f32x4.add(x1, x2), harea);
		const w12y = f32x4.mul(f32x4.add(y1, y2), harea);
		const w12z = f32x4.mul(f32x4.add(z1, z2), harea);
		f32.store(v11, f32.load(v11, V_X2) + f32x4.extract_lane(w23x, 0), V_X2);
		f32.store(v12, f32.load(v12, V_X2) + f32x4.extract_lane(w23x, 1), V_X2);
		f32.store(v13, f32.load(v13, V_X2) + f32x4.extract_lane(w23x, 2), V_X2);
		f32.store(v14, f32.load(v14, V_X2) + f32x4.extract_lane(w23x, 3), V_X2);
		f32.store(v11, f32.load(v11, V_Y2) + f32x4.extract_lane(w23y, 0), V_Y2);
		f32.store(v12, f32.load(v12, V_Y2) + f32x4.extract_lane(w23y, 1), V_Y2);
		f32.store(v13, f32.load(v13, V_Y2) + f32x4.extract_lane(w23y, 2), V_Y2);
		f32.store(v14, f32.load(v14, V_Y2) + f32x4.extract_lane(w23y, 3), V_Y2);
		f32.store(v11, f32.load(v11, V_Z2) + f32x4.extract_lane(w23z, 0), V_Z2);
		f32.store(v12, f32.load(v12, V_Z2) + f32x4.extract_lane(w23z, 1), V_Z2);
		f32.store(v13, f32.load(v13, V_Z2) + f32x4.extract_lane(w23z, 2), V_Z2);
		f32.store(v14, f32.load(v14, V_Z2) + f32x4.extract_lane(w23z, 3), V_Z2);
		f32.store(v21, f32.load(v21, V_X2) + f32x4.extract_lane(w31x, 0), V_X2);
		f32.store(v22, f32.load(v22, V_X2) + f32x4.extract_lane(w31x, 1), V_X2);
		f32.store(v23, f32.load(v23, V_X2) + f32x4.extract_lane(w31x, 2), V_X2);
		f32.store(v24, f32.load(v24, V_X2) + f32x4.extract_lane(w31x, 3), V_X2);
		f32.store(v21, f32.load(v21, V_Y2) + f32x4.extract_lane(w31y, 0), V_Y2);
		f32.store(v22, f32.load(v22, V_Y2) + f32x4.extract_lane(w31y, 1), V_Y2);
		f32.store(v23, f32.load(v23, V_Y2) + f32x4.extract_lane(w31y, 2), V_Y2);
		f32.store(v24, f32.load(v24, V_Y2) + f32x4.extract_lane(w31y, 3), V_Y2);
		f32.store(v21, f32.load(v21, V_Z2) + f32x4.extract_lane(w31z, 0), V_Z2);
		f32.store(v22, f32.load(v22, V_Z2) + f32x4.extract_lane(w31z, 1), V_Z2);
		f32.store(v23, f32.load(v23, V_Z2) + f32x4.extract_lane(w31z, 2), V_Z2);
		f32.store(v24, f32.load(v24, V_Z2) + f32x4.extract_lane(w31z, 3), V_Z2);
		f32.store(v31, f32.load(v31, V_X2) + f32x4.extract_lane(w12x, 0), V_X2);
		f32.store(v32, f32.load(v32, V_X2) + f32x4.extract_lane(w12x, 1), V_X2);
		f32.store(v33, f32.load(v33, V_X2) + f32x4.extract_lane(w12x, 2), V_X2);
		f32.store(v34, f32.load(v34, V_X2) + f32x4.extract_lane(w12x, 3), V_X2);
		f32.store(v31, f32.load(v31, V_Y2) + f32x4.extract_lane(w12y, 0), V_Y2);
		f32.store(v32, f32.load(v32, V_Y2) + f32x4.extract_lane(w12y, 1), V_Y2);
		f32.store(v33, f32.load(v33, V_Y2) + f32x4.extract_lane(w12y, 2), V_Y2);
		f32.store(v34, f32.load(v34, V_Y2) + f32x4.extract_lane(w12y, 3), V_Y2);
		f32.store(v31, f32.load(v31, V_Z2) + f32x4.extract_lane(w12z, 0), V_Z2);
		f32.store(v32, f32.load(v32, V_Z2) + f32x4.extract_lane(w12z, 1), V_Z2);
		f32.store(v33, f32.load(v33, V_Z2) + f32x4.extract_lane(w12z, 2), V_Z2);
		f32.store(v34, f32.load(v34, V_Z2) + f32x4.extract_lane(w12z, 3), V_Z2);
	}
	for (let i = 0; i < numVerts; i++) {
		const v = verts + i * VERTEX_STRIDE;
		const w = f32.load(v, V_WEIGHT);
		const invW: f32 = w == 0 ? 0 : 1 / w;
		const mx = f32.load(v, V_X2) * invW;
		const my = f32.load(v, V_Y2) * invW;
		const mz = f32.load(v, V_Z2) * invW;
		const x = f32.load(v, V_X);
		const y = f32.load(v, V_Y);
		const z = f32.load(v, V_Z);
		f32.store(v, (x + mx) * 0.5, V_X2);
		f32.store(v, (y + my) * 0.5, V_Y2);
		f32.store(v, (z + mz) * 0.5, V_Z2);
		f32.store(v, 0, V_X);
		f32.store(v, 0, V_Y);
		f32.store(v, 0, V_Z);
		f32.store(v, 0, V_WEIGHT);
	}
	// pass2
	for (let i = 0; i < numTris >> 2; i++) {
		const t1 = tris + (i << 2) * TRI_STRIDE;
		const t2 = t1 + TRI_STRIDE;
		const t3 = t2 + TRI_STRIDE;
		const t4 = t3 + TRI_STRIDE;
		const v11 = verts + i32.load(t1, T_V1) * VERTEX_STRIDE;
		const v12 = verts + i32.load(t2, T_V1) * VERTEX_STRIDE;
		const v13 = verts + i32.load(t3, T_V1) * VERTEX_STRIDE;
		const v14 = verts + i32.load(t4, T_V1) * VERTEX_STRIDE;
		const v21 = verts + i32.load(t1, T_V2) * VERTEX_STRIDE;
		const v22 = verts + i32.load(t2, T_V2) * VERTEX_STRIDE;
		const v23 = verts + i32.load(t3, T_V2) * VERTEX_STRIDE;
		const v24 = verts + i32.load(t4, T_V2) * VERTEX_STRIDE;
		const v31 = verts + i32.load(t1, T_V3) * VERTEX_STRIDE;
		const v32 = verts + i32.load(t2, T_V3) * VERTEX_STRIDE;
		const v33 = verts + i32.load(t3, T_V3) * VERTEX_STRIDE;
		const v34 = verts + i32.load(t4, T_V3) * VERTEX_STRIDE;
		const x11 = f32.load(v11, V_X2);
		const x12 = f32.load(v12, V_X2);
		const x13 = f32.load(v13, V_X2);
		const x14 = f32.load(v14, V_X2);
		const x1 = makef32x4(x11, x12, x13, x14);
		const y11 = f32.load(v11, V_Y2);
		const y12 = f32.load(v12, V_Y2);
		const y13 = f32.load(v13, V_Y2);
		const y14 = f32.load(v14, V_Y2);
		const y1 = makef32x4(y11, y12, y13, y14);
		const z11 = f32.load(v11, V_Z2);
		const z12 = f32.load(v12, V_Z2);
		const z13 = f32.load(v13, V_Z2);
		const z14 = f32.load(v14, V_Z2);
		const z1 = makef32x4(z11, z12, z13, z14);
		const x21 = f32.load(v21, V_X2);
		const x22 = f32.load(v22, V_X2);
		const x23 = f32.load(v23, V_X2);
		const x24 = f32.load(v24, V_X2);
		const x2 = makef32x4(x21, x22, x23, x24);
		const y21 = f32.load(v21, V_Y2);
		const y22 = f32.load(v22, V_Y2);
		const y23 = f32.load(v23, V_Y2);
		const y24 = f32.load(v24, V_Y2);
		const y2 = makef32x4(y21, y22, y23, y24);
		const z21 = f32.load(v21, V_Z2);
		const z22 = f32.load(v22, V_Z2);
		const z23 = f32.load(v23, V_Z2);
		const z24 = f32.load(v24, V_Z2);
		const z2 = makef32x4(z21, z22, z23, z24);
		const x31 = f32.load(v31, V_X2);
		const x32 = f32.load(v32, V_X2);
		const x33 = f32.load(v33, V_X2);
		const x34 = f32.load(v34, V_X2);
		const x3 = makef32x4(x31, x32, x33, x34);
		const y31 = f32.load(v31, V_Y2);
		const y32 = f32.load(v32, V_Y2);
		const y33 = f32.load(v33, V_Y2);
		const y34 = f32.load(v34, V_Y2);
		const y3 = makef32x4(y31, y32, y33, y34);
		const z31 = f32.load(v31, V_Z2);
		const z32 = f32.load(v32, V_Z2);
		const z33 = f32.load(v33, V_Z2);
		const z34 = f32.load(v34, V_Z2);
		const z3 = makef32x4(z31, z32, z33, z34);
		const v12x = f32x4.sub(x2, x1);
		const v12y = f32x4.sub(y2, y1);
		const v12z = f32x4.sub(z2, z1);
		const v13x = f32x4.sub(x3, x1);
		const v13y = f32x4.sub(y3, y1);
		const v13z = f32x4.sub(z3, z1);
		// v12 cross v13
		const cx = f32x4.sub(f32x4.mul(v12y, v13z), f32x4.mul(v12z, v13y));
		const cy = f32x4.sub(f32x4.mul(v12z, v13x), f32x4.mul(v12x, v13z));
		const cz = f32x4.sub(f32x4.mul(v12x, v13y), f32x4.mul(v12y, v13x));
		const area = f32x4.sqrt(f32x4.add(f32x4.add(f32x4pow2(cx), f32x4pow2(cy)), f32x4pow2(cz)));
		// const area = f32x4.splat(1);
		const area1 = f32x4.extract_lane(area, 0);
		const area2 = f32x4.extract_lane(area, 1);
		const area3 = f32x4.extract_lane(area, 2);
		const area4 = f32x4.extract_lane(area, 3);
		f32.store(v11, f32.load(v11, V_WEIGHT) + area1, V_WEIGHT);
		f32.store(v12, f32.load(v12, V_WEIGHT) + area2, V_WEIGHT);
		f32.store(v13, f32.load(v13, V_WEIGHT) + area3, V_WEIGHT);
		f32.store(v14, f32.load(v14, V_WEIGHT) + area4, V_WEIGHT);
		f32.store(v21, f32.load(v21, V_WEIGHT) + area1, V_WEIGHT);
		f32.store(v22, f32.load(v22, V_WEIGHT) + area2, V_WEIGHT);
		f32.store(v23, f32.load(v23, V_WEIGHT) + area3, V_WEIGHT);
		f32.store(v24, f32.load(v24, V_WEIGHT) + area4, V_WEIGHT);
		f32.store(v31, f32.load(v31, V_WEIGHT) + area1, V_WEIGHT);
		f32.store(v32, f32.load(v32, V_WEIGHT) + area2, V_WEIGHT);
		f32.store(v33, f32.load(v33, V_WEIGHT) + area3, V_WEIGHT);
		f32.store(v34, f32.load(v34, V_WEIGHT) + area4, V_WEIGHT);
		const harea = f32x4.mul(area, f32x4.splat(0.5));
		const w23x = f32x4.mul(f32x4.add(x2, x3), harea);
		const w23y = f32x4.mul(f32x4.add(y2, y3), harea);
		const w23z = f32x4.mul(f32x4.add(z2, z3), harea);
		const w31x = f32x4.mul(f32x4.add(x3, x1), harea);
		const w31y = f32x4.mul(f32x4.add(y3, y1), harea);
		const w31z = f32x4.mul(f32x4.add(z3, z1), harea);
		const w12x = f32x4.mul(f32x4.add(x1, x2), harea);
		const w12y = f32x4.mul(f32x4.add(y1, y2), harea);
		const w12z = f32x4.mul(f32x4.add(z1, z2), harea);
		f32.store(v11, f32.load(v11, V_X) + f32x4.extract_lane(w23x, 0), V_X);
		f32.store(v12, f32.load(v12, V_X) + f32x4.extract_lane(w23x, 1), V_X);
		f32.store(v13, f32.load(v13, V_X) + f32x4.extract_lane(w23x, 2), V_X);
		f32.store(v14, f32.load(v14, V_X) + f32x4.extract_lane(w23x, 3), V_X);
		f32.store(v11, f32.load(v11, V_Y) + f32x4.extract_lane(w23y, 0), V_Y);
		f32.store(v12, f32.load(v12, V_Y) + f32x4.extract_lane(w23y, 1), V_Y);
		f32.store(v13, f32.load(v13, V_Y) + f32x4.extract_lane(w23y, 2), V_Y);
		f32.store(v14, f32.load(v14, V_Y) + f32x4.extract_lane(w23y, 3), V_Y);
		f32.store(v11, f32.load(v11, V_Z) + f32x4.extract_lane(w23z, 0), V_Z);
		f32.store(v12, f32.load(v12, V_Z) + f32x4.extract_lane(w23z, 1), V_Z);
		f32.store(v13, f32.load(v13, V_Z) + f32x4.extract_lane(w23z, 2), V_Z);
		f32.store(v14, f32.load(v14, V_Z) + f32x4.extract_lane(w23z, 3), V_Z);
		f32.store(v21, f32.load(v21, V_X) + f32x4.extract_lane(w31x, 0), V_X);
		f32.store(v22, f32.load(v22, V_X) + f32x4.extract_lane(w31x, 1), V_X);
		f32.store(v23, f32.load(v23, V_X) + f32x4.extract_lane(w31x, 2), V_X);
		f32.store(v24, f32.load(v24, V_X) + f32x4.extract_lane(w31x, 3), V_X);
		f32.store(v21, f32.load(v21, V_Y) + f32x4.extract_lane(w31y, 0), V_Y);
		f32.store(v22, f32.load(v22, V_Y) + f32x4.extract_lane(w31y, 1), V_Y);
		f32.store(v23, f32.load(v23, V_Y) + f32x4.extract_lane(w31y, 2), V_Y);
		f32.store(v24, f32.load(v24, V_Y) + f32x4.extract_lane(w31y, 3), V_Y);
		f32.store(v21, f32.load(v21, V_Z) + f32x4.extract_lane(w31z, 0), V_Z);
		f32.store(v22, f32.load(v22, V_Z) + f32x4.extract_lane(w31z, 1), V_Z);
		f32.store(v23, f32.load(v23, V_Z) + f32x4.extract_lane(w31z, 2), V_Z);
		f32.store(v24, f32.load(v24, V_Z) + f32x4.extract_lane(w31z, 3), V_Z);
		f32.store(v31, f32.load(v31, V_X) + f32x4.extract_lane(w12x, 0), V_X);
		f32.store(v32, f32.load(v32, V_X) + f32x4.extract_lane(w12x, 1), V_X);
		f32.store(v33, f32.load(v33, V_X) + f32x4.extract_lane(w12x, 2), V_X);
		f32.store(v34, f32.load(v34, V_X) + f32x4.extract_lane(w12x, 3), V_X);
		f32.store(v31, f32.load(v31, V_Y) + f32x4.extract_lane(w12y, 0), V_Y);
		f32.store(v32, f32.load(v32, V_Y) + f32x4.extract_lane(w12y, 1), V_Y);
		f32.store(v33, f32.load(v33, V_Y) + f32x4.extract_lane(w12y, 2), V_Y);
		f32.store(v34, f32.load(v34, V_Y) + f32x4.extract_lane(w12y, 3), V_Y);
		f32.store(v31, f32.load(v31, V_Z) + f32x4.extract_lane(w12z, 0), V_Z);
		f32.store(v32, f32.load(v32, V_Z) + f32x4.extract_lane(w12z, 1), V_Z);
		f32.store(v33, f32.load(v33, V_Z) + f32x4.extract_lane(w12z, 2), V_Z);
		f32.store(v34, f32.load(v34, V_Z) + f32x4.extract_lane(w12z, 3), V_Z);
	}
	for (let i = 0; i < numVerts; i++) {
		const v = verts + i * VERTEX_STRIDE;
		const w = f32.load(v, V_WEIGHT);
		const invW: f32 = w == 0 ? 0 : 1 / w;
		const mx = f32.load(v, V_X) * invW;
		const my = f32.load(v, V_Y) * invW;
		const mz = f32.load(v, V_Z) * invW;
		const x = f32.load(v, V_X2);
		const y = f32.load(v, V_Y2);
		const z = f32.load(v, V_Z2);
		f32.store(v, (x + mx) * 0.5, V_X);
		f32.store(v, (y + my) * 0.5, V_Y);
		f32.store(v, (z + mz) * 0.5, V_Z);
	}
	// compute normals
	for (let i = 0; i < numTris >> 2; i++) {
		const t1 = tris + (i << 2) * TRI_STRIDE;
		const t2 = t1 + TRI_STRIDE;
		const t3 = t2 + TRI_STRIDE;
		const t4 = t3 + TRI_STRIDE;
		const v11 = verts + i32.load(t1, T_V1) * VERTEX_STRIDE;
		const v12 = verts + i32.load(t2, T_V1) * VERTEX_STRIDE;
		const v13 = verts + i32.load(t3, T_V1) * VERTEX_STRIDE;
		const v14 = verts + i32.load(t4, T_V1) * VERTEX_STRIDE;
		const v21 = verts + i32.load(t1, T_V2) * VERTEX_STRIDE;
		const v22 = verts + i32.load(t2, T_V2) * VERTEX_STRIDE;
		const v23 = verts + i32.load(t3, T_V2) * VERTEX_STRIDE;
		const v24 = verts + i32.load(t4, T_V2) * VERTEX_STRIDE;
		const v31 = verts + i32.load(t1, T_V3) * VERTEX_STRIDE;
		const v32 = verts + i32.load(t2, T_V3) * VERTEX_STRIDE;
		const v33 = verts + i32.load(t3, T_V3) * VERTEX_STRIDE;
		const v34 = verts + i32.load(t4, T_V3) * VERTEX_STRIDE;
		const x11 = f32.load(v11, V_X);
		const x12 = f32.load(v12, V_X);
		const x13 = f32.load(v13, V_X);
		const x14 = f32.load(v14, V_X);
		const x1 = makef32x4(x11, x12, x13, x14);
		const y11 = f32.load(v11, V_Y);
		const y12 = f32.load(v12, V_Y);
		const y13 = f32.load(v13, V_Y);
		const y14 = f32.load(v14, V_Y);
		const y1 = makef32x4(y11, y12, y13, y14);
		const z11 = f32.load(v11, V_Z);
		const z12 = f32.load(v12, V_Z);
		const z13 = f32.load(v13, V_Z);
		const z14 = f32.load(v14, V_Z);
		const z1 = makef32x4(z11, z12, z13, z14);
		const x21 = f32.load(v21, V_X);
		const x22 = f32.load(v22, V_X);
		const x23 = f32.load(v23, V_X);
		const x24 = f32.load(v24, V_X);
		const x2 = makef32x4(x21, x22, x23, x24);
		const y21 = f32.load(v21, V_Y);
		const y22 = f32.load(v22, V_Y);
		const y23 = f32.load(v23, V_Y);
		const y24 = f32.load(v24, V_Y);
		const y2 = makef32x4(y21, y22, y23, y24);
		const z21 = f32.load(v21, V_Z);
		const z22 = f32.load(v22, V_Z);
		const z23 = f32.load(v23, V_Z);
		const z24 = f32.load(v24, V_Z);
		const z2 = makef32x4(z21, z22, z23, z24);
		const x31 = f32.load(v31, V_X);
		const x32 = f32.load(v32, V_X);
		const x33 = f32.load(v33, V_X);
		const x34 = f32.load(v34, V_X);
		const x3 = makef32x4(x31, x32, x33, x34);
		const y31 = f32.load(v31, V_Y);
		const y32 = f32.load(v32, V_Y);
		const y33 = f32.load(v33, V_Y);
		const y34 = f32.load(v34, V_Y);
		const y3 = makef32x4(y31, y32, y33, y34);
		const z31 = f32.load(v31, V_Z);
		const z32 = f32.load(v32, V_Z);
		const z33 = f32.load(v33, V_Z);
		const z34 = f32.load(v34, V_Z);
		const z3 = makef32x4(z31, z32, z33, z34);
		const v12x = f32x4.sub(x2, x1);
		const v12y = f32x4.sub(y2, y1);
		const v12z = f32x4.sub(z2, z1);
		const v13x = f32x4.sub(x3, x1);
		const v13y = f32x4.sub(y3, y1);
		const v13z = f32x4.sub(z3, z1);
		// v12 cross v13
		const nx = f32x4.sub(f32x4.mul(v12y, v13z), f32x4.mul(v12z, v13y));
		const ny = f32x4.sub(f32x4.mul(v12z, v13x), f32x4.mul(v12x, v13z));
		const nz = f32x4.sub(f32x4.mul(v12x, v13y), f32x4.mul(v12y, v13x));
		// add to normals
		f32.store(v11, f32.load(v11, V_NX) + f32x4.extract_lane(nx, 0), V_NX);
		f32.store(v12, f32.load(v12, V_NX) + f32x4.extract_lane(nx, 1), V_NX);
		f32.store(v13, f32.load(v13, V_NX) + f32x4.extract_lane(nx, 2), V_NX);
		f32.store(v14, f32.load(v14, V_NX) + f32x4.extract_lane(nx, 3), V_NX);
		f32.store(v11, f32.load(v11, V_NY) + f32x4.extract_lane(ny, 0), V_NY);
		f32.store(v12, f32.load(v12, V_NY) + f32x4.extract_lane(ny, 1), V_NY);
		f32.store(v13, f32.load(v13, V_NY) + f32x4.extract_lane(ny, 2), V_NY);
		f32.store(v14, f32.load(v14, V_NY) + f32x4.extract_lane(ny, 3), V_NY);
		f32.store(v11, f32.load(v11, V_NZ) + f32x4.extract_lane(nz, 0), V_NZ);
		f32.store(v12, f32.load(v12, V_NZ) + f32x4.extract_lane(nz, 1), V_NZ);
		f32.store(v13, f32.load(v13, V_NZ) + f32x4.extract_lane(nz, 2), V_NZ);
		f32.store(v14, f32.load(v14, V_NZ) + f32x4.extract_lane(nz, 3), V_NZ);
		f32.store(v21, f32.load(v21, V_NX) + f32x4.extract_lane(nx, 0), V_NX);
		f32.store(v22, f32.load(v22, V_NX) + f32x4.extract_lane(nx, 1), V_NX);
		f32.store(v23, f32.load(v23, V_NX) + f32x4.extract_lane(nx, 2), V_NX);
		f32.store(v24, f32.load(v24, V_NX) + f32x4.extract_lane(nx, 3), V_NX);
		f32.store(v21, f32.load(v21, V_NY) + f32x4.extract_lane(ny, 0), V_NY);
		f32.store(v22, f32.load(v22, V_NY) + f32x4.extract_lane(ny, 1), V_NY);
		f32.store(v23, f32.load(v23, V_NY) + f32x4.extract_lane(ny, 2), V_NY);
		f32.store(v24, f32.load(v24, V_NY) + f32x4.extract_lane(ny, 3), V_NY);
		f32.store(v21, f32.load(v21, V_NZ) + f32x4.extract_lane(nz, 0), V_NZ);
		f32.store(v22, f32.load(v22, V_NZ) + f32x4.extract_lane(nz, 1), V_NZ);
		f32.store(v23, f32.load(v23, V_NZ) + f32x4.extract_lane(nz, 2), V_NZ);
		f32.store(v24, f32.load(v24, V_NZ) + f32x4.extract_lane(nz, 3), V_NZ);
		f32.store(v31, f32.load(v31, V_NX) + f32x4.extract_lane(nx, 0), V_NX);
		f32.store(v32, f32.load(v32, V_NX) + f32x4.extract_lane(nx, 1), V_NX);
		f32.store(v33, f32.load(v33, V_NX) + f32x4.extract_lane(nx, 2), V_NX);
		f32.store(v34, f32.load(v34, V_NX) + f32x4.extract_lane(nx, 3), V_NX);
		f32.store(v31, f32.load(v31, V_NY) + f32x4.extract_lane(ny, 0), V_NY);
		f32.store(v32, f32.load(v32, V_NY) + f32x4.extract_lane(ny, 1), V_NY);
		f32.store(v33, f32.load(v33, V_NY) + f32x4.extract_lane(ny, 2), V_NY);
		f32.store(v34, f32.load(v34, V_NY) + f32x4.extract_lane(ny, 3), V_NY);
		f32.store(v31, f32.load(v31, V_NZ) + f32x4.extract_lane(nz, 0), V_NZ);
		f32.store(v32, f32.load(v32, V_NZ) + f32x4.extract_lane(nz, 1), V_NZ);
		f32.store(v33, f32.load(v33, V_NZ) + f32x4.extract_lane(nz, 2), V_NZ);
		f32.store(v34, f32.load(v34, V_NZ) + f32x4.extract_lane(nz, 3), V_NZ);
	}
	// smooth normals
	for (let pass = 0; pass < 4; pass++) {
		for (let i = 0; i < numVerts; i++) {
			const v = verts + i * VERTEX_STRIDE;
			const nx = f32.load(v, V_NX);
			const ny = f32.load(v, V_NY);
			const nz = f32.load(v, V_NZ);
			const len2 = nx * nx + ny * ny + nz * nz;
			const invLen = f32(1) / sqrt(len2 + 1e-9);
			f32.store(v, nx * invLen, V_X2);
			f32.store(v, ny * invLen, V_Y2);
			f32.store(v, nz * invLen, V_Z2);
			f32.store(v, 0, V_NX);
			f32.store(v, 0, V_NY);
			f32.store(v, 0, V_NZ);
		}
		for (let i = 0; i < numTris >> 2; i++) {
			const t1 = tris + (i << 2) * TRI_STRIDE;
			const t2 = t1 + TRI_STRIDE;
			const t3 = t2 + TRI_STRIDE;
			const t4 = t3 + TRI_STRIDE;
			const v11 = verts + i32.load(t1, T_V1) * VERTEX_STRIDE;
			const v12 = verts + i32.load(t2, T_V1) * VERTEX_STRIDE;
			const v13 = verts + i32.load(t3, T_V1) * VERTEX_STRIDE;
			const v14 = verts + i32.load(t4, T_V1) * VERTEX_STRIDE;
			const v21 = verts + i32.load(t1, T_V2) * VERTEX_STRIDE;
			const v22 = verts + i32.load(t2, T_V2) * VERTEX_STRIDE;
			const v23 = verts + i32.load(t3, T_V2) * VERTEX_STRIDE;
			const v24 = verts + i32.load(t4, T_V2) * VERTEX_STRIDE;
			const v31 = verts + i32.load(t1, T_V3) * VERTEX_STRIDE;
			const v32 = verts + i32.load(t2, T_V3) * VERTEX_STRIDE;
			const v33 = verts + i32.load(t3, T_V3) * VERTEX_STRIDE;
			const v34 = verts + i32.load(t4, T_V3) * VERTEX_STRIDE;
			const nx11 = f32.load(v11, V_X2);
			const nx12 = f32.load(v12, V_X2);
			const nx13 = f32.load(v13, V_X2);
			const nx14 = f32.load(v14, V_X2);
			const nx1 = makef32x4(nx11, nx12, nx13, nx14);
			const ny11 = f32.load(v11, V_Y2);
			const ny12 = f32.load(v12, V_Y2);
			const ny13 = f32.load(v13, V_Y2);
			const ny14 = f32.load(v14, V_Y2);
			const ny1 = makef32x4(ny11, ny12, ny13, ny14);
			const nz11 = f32.load(v11, V_Z2);
			const nz12 = f32.load(v12, V_Z2);
			const nz13 = f32.load(v13, V_Z2);
			const nz14 = f32.load(v14, V_Z2);
			const nz1 = makef32x4(nz11, nz12, nz13, nz14);
			const nx21 = f32.load(v21, V_X2);
			const nx22 = f32.load(v22, V_X2);
			const nx23 = f32.load(v23, V_X2);
			const nx24 = f32.load(v24, V_X2);
			const nx2 = makef32x4(nx21, nx22, nx23, nx24);
			const ny21 = f32.load(v21, V_Y2);
			const ny22 = f32.load(v22, V_Y2);
			const ny23 = f32.load(v23, V_Y2);
			const ny24 = f32.load(v24, V_Y2);
			const ny2 = makef32x4(ny21, ny22, ny23, ny24);
			const nz21 = f32.load(v21, V_Z2);
			const nz22 = f32.load(v22, V_Z2);
			const nz23 = f32.load(v23, V_Z2);
			const nz24 = f32.load(v24, V_Z2);
			const nz2 = makef32x4(nz21, nz22, nz23, nz24);
			const nx31 = f32.load(v31, V_X2);
			const nx32 = f32.load(v32, V_X2);
			const nx33 = f32.load(v33, V_X2);
			const nx34 = f32.load(v34, V_X2);
			const nx3 = makef32x4(nx31, nx32, nx33, nx34);
			const ny31 = f32.load(v31, V_Y2);
			const ny32 = f32.load(v32, V_Y2);
			const ny33 = f32.load(v33, V_Y2);
			const ny34 = f32.load(v34, V_Y2);
			const ny3 = makef32x4(ny31, ny32, ny33, ny34);
			const nz31 = f32.load(v31, V_Z2);
			const nz32 = f32.load(v32, V_Z2);
			const nz33 = f32.load(v33, V_Z2);
			const nz34 = f32.load(v34, V_Z2);
			const nz3 = makef32x4(nz31, nz32, nz33, nz34);
			const nx = f32x4.add(f32x4.add(nx1, nx2), nx3);
			const ny = f32x4.add(f32x4.add(ny1, ny2), ny3);
			const nz = f32x4.add(f32x4.add(nz1, nz2), nz3);
			f32.store(v11, f32.load(v11, V_NX) + f32x4.extract_lane(nx, 0), V_NX);
			f32.store(v12, f32.load(v12, V_NX) + f32x4.extract_lane(nx, 1), V_NX);
			f32.store(v13, f32.load(v13, V_NX) + f32x4.extract_lane(nx, 2), V_NX);
			f32.store(v14, f32.load(v14, V_NX) + f32x4.extract_lane(nx, 3), V_NX);
			f32.store(v11, f32.load(v11, V_NY) + f32x4.extract_lane(ny, 0), V_NY);
			f32.store(v12, f32.load(v12, V_NY) + f32x4.extract_lane(ny, 1), V_NY);
			f32.store(v13, f32.load(v13, V_NY) + f32x4.extract_lane(ny, 2), V_NY);
			f32.store(v14, f32.load(v14, V_NY) + f32x4.extract_lane(ny, 3), V_NY);
			f32.store(v11, f32.load(v11, V_NZ) + f32x4.extract_lane(nz, 0), V_NZ);
			f32.store(v12, f32.load(v12, V_NZ) + f32x4.extract_lane(nz, 1), V_NZ);
			f32.store(v13, f32.load(v13, V_NZ) + f32x4.extract_lane(nz, 2), V_NZ);
			f32.store(v14, f32.load(v14, V_NZ) + f32x4.extract_lane(nz, 3), V_NZ);
			f32.store(v21, f32.load(v21, V_NX) + f32x4.extract_lane(nx, 0), V_NX);
			f32.store(v22, f32.load(v22, V_NX) + f32x4.extract_lane(nx, 1), V_NX);
			f32.store(v23, f32.load(v23, V_NX) + f32x4.extract_lane(nx, 2), V_NX);
			f32.store(v24, f32.load(v24, V_NX) + f32x4.extract_lane(nx, 3), V_NX);
			f32.store(v21, f32.load(v21, V_NY) + f32x4.extract_lane(ny, 0), V_NY);
			f32.store(v22, f32.load(v22, V_NY) + f32x4.extract_lane(ny, 1), V_NY);
			f32.store(v23, f32.load(v23, V_NY) + f32x4.extract_lane(ny, 2), V_NY);
			f32.store(v24, f32.load(v24, V_NY) + f32x4.extract_lane(ny, 3), V_NY);
			f32.store(v21, f32.load(v21, V_NZ) + f32x4.extract_lane(nz, 0), V_NZ);
			f32.store(v22, f32.load(v22, V_NZ) + f32x4.extract_lane(nz, 1), V_NZ);
			f32.store(v23, f32.load(v23, V_NZ) + f32x4.extract_lane(nz, 2), V_NZ);
			f32.store(v24, f32.load(v24, V_NZ) + f32x4.extract_lane(nz, 3), V_NZ);
			f32.store(v31, f32.load(v31, V_NX) + f32x4.extract_lane(nx, 0), V_NX);
			f32.store(v32, f32.load(v32, V_NX) + f32x4.extract_lane(nx, 1), V_NX);
			f32.store(v33, f32.load(v33, V_NX) + f32x4.extract_lane(nx, 2), V_NX);
			f32.store(v34, f32.load(v34, V_NX) + f32x4.extract_lane(nx, 3), V_NX);
			f32.store(v31, f32.load(v31, V_NY) + f32x4.extract_lane(ny, 0), V_NY);
			f32.store(v32, f32.load(v32, V_NY) + f32x4.extract_lane(ny, 1), V_NY);
			f32.store(v33, f32.load(v33, V_NY) + f32x4.extract_lane(ny, 2), V_NY);
			f32.store(v34, f32.load(v34, V_NY) + f32x4.extract_lane(ny, 3), V_NY);
			f32.store(v31, f32.load(v31, V_NZ) + f32x4.extract_lane(nz, 0), V_NZ);
			f32.store(v32, f32.load(v32, V_NZ) + f32x4.extract_lane(nz, 1), V_NZ);
			f32.store(v33, f32.load(v33, V_NZ) + f32x4.extract_lane(nz, 2), V_NZ);
			f32.store(v34, f32.load(v34, V_NZ) + f32x4.extract_lane(nz, 3), V_NZ);
		}
	}
	// export final mesh
	numTris = numOrigTris;
	for (let i = 0; i < numVerts; i++) {
		const v = verts + i * VERTEX_STRIDE;
		const x = f32.load(v, V_X);
		const y = f32.load(v, V_Y);
		const z = f32.load(v, V_Z);
		const nx = f32.load(v, V_NX);
		const ny = f32.load(v, V_NY);
		const nz = f32.load(v, V_NZ);
		const fv = fverts + i * FINAL_VERTEX_STRIDE;
		f32.store(fv, x, FV_X);
		f32.store(fv, y, FV_Y);
		f32.store(fv, z, FV_Z);
		f32.store(fv, nx, FV_NX);
		f32.store(fv, ny, FV_NY);
		f32.store(fv, nz, FV_NZ);
	}
}
