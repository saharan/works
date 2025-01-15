#include "wasm.h"
#include "wasm_simd128.h"
#include <cstring>

constexpr f32 AERATION_THRESHOLD = 0.7;
constexpr f32 AERATION_COEFF = 20.0;
constexpr f32 AERATION_BLUR = 0.01;
constexpr f32 AERATION_DAMP = 0.992;

constexpr f32 PDELTA = 0.5;
constexpr f32 DENSITY = 1 / (PDELTA * PDELTA);
constexpr f32 INV_DENSITY = 1 / DENSITY;

struct Particle {
	f32 aeration;
	f32 posx;
	f32 posy;
	f32 velx;
	f32 vely;
	f32 gvel00;
	f32 gvel01;
	f32 gvel10;
	f32 gvel11;
	f32 dens;
};

struct VectorizedParticle {
	v128 aeration;
	v128 density;
	v128 posx;
	v128 posy;
	v128 velx;
	v128 vely;
	v128 gvel00;
	v128 gvel01;
	v128 gvel10;
	v128 gvel11;

	v128 dx;
	v128 dy;

	v128 w00;
	v128 w01;
	v128 w02;
	v128 w10;
	v128 w11;
	v128 w12;
	v128 w20;
	v128 w21;
	v128 w22;

	v128 c00;
	v128 c01;
	v128 c02;
	v128 c10;
	v128 c11;
	v128 c12;
	v128 c20;
	v128 c21;
	v128 c22;
};

struct Cell {
	f32 mass;
	f32 aeration;
	f32 velx;
	f32 vely;
	f32 dvelx;
	f32 dvely;
};

constexpr i32 MAX_PARTICLES = 262144;
constexpr i32 MAX_CELLS = 262144;

Particle ps[MAX_PARTICLES];
VectorizedParticle vps[MAX_PARTICLES >> 2];

WASM_EXPORT i32 numP = 0;

Cell cs[MAX_CELLS];
i32 gridW = 0;
i32 gridH = 0;
i32 numC = 0;

inline v128 f32x4_pow2(v128 x) {
	return wasm_f32x4_mul(x, x);
}

inline void mirror(i32 c1, i32 c2) {
	const f32 m = cs[c1].mass + cs[c2].mass;
	const f32 mx = cs[c1].velx + cs[c2].velx;
	const f32 my = cs[c1].vely + cs[c2].vely;
	cs[c1].mass = m;
	cs[c2].mass = m;
	cs[c1].velx = mx;
	cs[c2].velx = mx;
	cs[c1].vely = my;
	cs[c2].vely = my;
}

inline void mirror2(i32 c1, i32 c2, bool flipx, bool flipy) {
	if (flipx) {
		const f32 subx = cs[c1].dvelx - cs[c2].dvelx;
		cs[c1].dvelx = subx;
		cs[c2].dvelx = -subx;
	} else {
		const f32 sumx = cs[c1].dvelx + cs[c2].dvelx;
		cs[c1].dvelx = sumx;
		cs[c2].dvelx = sumx;
	}
	if (flipy) {
		const f32 suby = cs[c1].dvely - cs[c2].dvely;
		cs[c1].dvely = suby;
		cs[c2].dvely = -suby;
	} else {
		const f32 sumy = cs[c1].dvely + cs[c2].dvely;
		cs[c1].dvely = sumy;
		cs[c2].dvely = sumy;
	}
}

WASM_EXPORT i32 particles() {
	return ptr(ps);
}

WASM_EXPORT i32 cells() {
	return ptr(cs);
}

WASM_EXPORT void setGrid(i32 gw, i32 gh) {
	gridW = gw;
	gridH = gh;
}

WASM_EXPORT void p2g() {
	numC = gridW * gridH;
	memset(cs, 0, numC * sizeof(Cell));

	int origNumP = numP;
	int numP = origNumP;

	// pad to multiple of 4
	while (numP & 3) {
		// copy the last particle to pad
		ps[numP] = ps[numP - 1];
		numP++;
	}

	const v128 igridWs = wasm_i32x4_splat(gridW);
	const v128 f1s = wasm_f32x4_const_splat(1);
	const v128 f05s = wasm_f32x4_const_splat(0.5);
	const v128 f75s = wasm_f32x4_const_splat(0.75);
	const v128 f0s = wasm_f32x4_const_splat(0);
	const v128 i1s = wasm_i32x4_const_splat(1);
	const v128 i0s = wasm_i32x4_const_splat(0);

	// mass and momentum transfer
	for (i32 i = 0; i < numP; i += 4) {
		i32 i1 = i;
		i32 i2 = i + 1;
		i32 i3 = i + 2;
		i32 i4 = i + 3;
		const Particle& p1 = ps[i1];
		const Particle& p2 = ps[i2];
		const Particle& p3 = ps[i3];
		const Particle& p4 = ps[i4];
		VectorizedParticle& vp = vps[i >> 2];
		const v128 wmask =
			wasm_i32x4_make(-1, -(i2 < origNumP), -(i3 < origNumP), -(i4 < origNumP)); // mask out padding
		vp.aeration = wasm_f32x4_make(p1.aeration, p2.aeration, p3.aeration, p4.aeration);
		vp.posx = wasm_f32x4_make(p1.posx, p2.posx, p3.posx, p4.posx);
		vp.posy = wasm_f32x4_make(p1.posy, p2.posy, p3.posy, p4.posy);
		vp.velx = wasm_f32x4_make(p1.velx, p2.velx, p3.velx, p4.velx);
		vp.vely = wasm_f32x4_make(p1.vely, p2.vely, p3.vely, p4.vely);
		vp.gvel00 = wasm_f32x4_make(p1.gvel00, p2.gvel00, p3.gvel00, p4.gvel00);
		vp.gvel01 = wasm_f32x4_make(p1.gvel01, p2.gvel01, p3.gvel01, p4.gvel01);
		vp.gvel10 = wasm_f32x4_make(p1.gvel10, p2.gvel10, p3.gvel10, p4.gvel10);
		vp.gvel11 = wasm_f32x4_make(p1.gvel11, p2.gvel11, p3.gvel11, p4.gvel11);
		const v128 gx = wasm_f32x4_floor(vp.posx);
		const v128 gy = wasm_f32x4_floor(vp.posy);
		const v128 igx = wasm_i32x4_trunc_sat_f32x4(gx);
		const v128 igy = wasm_i32x4_trunc_sat_f32x4(gy);
		const v128 cidx =
			wasm_i32x4_add(wasm_i32x4_mul(wasm_i32x4_sub(igy, i1s), igridWs), wasm_i32x4_sub(igx, i1s));

		vp.dx = wasm_f32x4_sub(wasm_f32x4_add(gx, f05s), vp.posx);
		vp.dy = wasm_f32x4_sub(wasm_f32x4_add(gy, f05s), vp.posy);
		const v128 wx0 = wasm_v128_and(wasm_f32x4_mul(f32x4_pow2(wasm_f32x4_add(vp.dx, f05s)), f05s), wmask);
		const v128 wx1 = wasm_v128_and(wasm_f32x4_sub(f75s, f32x4_pow2(vp.dx)), wmask);
		const v128 wx2 = wasm_v128_and(wasm_f32x4_mul(f32x4_pow2(wasm_f32x4_sub(vp.dx, f05s)), f05s), wmask);
		const v128 wy0 = wasm_f32x4_mul(f32x4_pow2(wasm_f32x4_add(vp.dy, f05s)), f05s);
		const v128 wy1 = wasm_f32x4_sub(f75s, f32x4_pow2(vp.dy));
		const v128 wy2 = wasm_f32x4_mul(f32x4_pow2(wasm_f32x4_sub(vp.dy, f05s)), f05s);
		vp.w00 = wasm_f32x4_mul(wy0, wx0);
		vp.w01 = wasm_f32x4_mul(wy0, wx1);
		vp.w02 = wasm_f32x4_mul(wy0, wx2);
		vp.w10 = wasm_f32x4_mul(wy1, wx0);
		vp.w11 = wasm_f32x4_mul(wy1, wx1);
		vp.w12 = wasm_f32x4_mul(wy1, wx2);
		vp.w20 = wasm_f32x4_mul(wy2, wx0);
		vp.w21 = wasm_f32x4_mul(wy2, wx1);
		vp.w22 = wasm_f32x4_mul(wy2, wx2);

		vp.c00 = cidx;
		vp.c01 = wasm_i32x4_add(vp.c00, i1s);
		vp.c02 = wasm_i32x4_add(vp.c01, i1s);
		vp.c10 = wasm_i32x4_add(vp.c00, igridWs);
		vp.c11 = wasm_i32x4_add(vp.c01, igridWs);
		vp.c12 = wasm_i32x4_add(vp.c02, igridWs);
		vp.c20 = wasm_i32x4_add(vp.c10, igridWs);
		vp.c21 = wasm_i32x4_add(vp.c11, igridWs);
		vp.c22 = wasm_i32x4_add(vp.c12, igridWs);

		const v128 gv00x = wasm_f32x4_mul(vp.gvel00, vp.dx);
		const v128 gv01y = wasm_f32x4_mul(vp.gvel01, vp.dy);
		const v128 gv10x = wasm_f32x4_mul(vp.gvel10, vp.dx);
		const v128 gv11y = wasm_f32x4_mul(vp.gvel11, vp.dy);

		const v128 cvx = wasm_f32x4_add(vp.velx, wasm_f32x4_add(gv00x, gv01y));
		const v128 cvy = wasm_f32x4_add(vp.vely, wasm_f32x4_add(gv10x, gv11y));

		v128 ci;
		v128 w;
		v128 wvx;
		v128 wvy;

#define VISIT_CELL()                                   \
	{                                                  \
		v128 wa = wasm_f32x4_mul(w, vp.aeration);      \
		Cell& c0 = cs[wasm_i32x4_extract_lane(ci, 0)]; \
		Cell& c1 = cs[wasm_i32x4_extract_lane(ci, 1)]; \
		Cell& c2 = cs[wasm_i32x4_extract_lane(ci, 2)]; \
		Cell& c3 = cs[wasm_i32x4_extract_lane(ci, 3)]; \
		c0.mass += wasm_f32x4_extract_lane(w, 0);      \
		c1.mass += wasm_f32x4_extract_lane(w, 1);      \
		c2.mass += wasm_f32x4_extract_lane(w, 2);      \
		c3.mass += wasm_f32x4_extract_lane(w, 3);      \
		c0.aeration += wasm_f32x4_extract_lane(wa, 0); \
		c1.aeration += wasm_f32x4_extract_lane(wa, 1); \
		c2.aeration += wasm_f32x4_extract_lane(wa, 2); \
		c3.aeration += wasm_f32x4_extract_lane(wa, 3); \
		c0.velx += wasm_f32x4_extract_lane(wvx, 0);    \
		c1.velx += wasm_f32x4_extract_lane(wvx, 1);    \
		c2.velx += wasm_f32x4_extract_lane(wvx, 2);    \
		c3.velx += wasm_f32x4_extract_lane(wvx, 3);    \
		c0.vely += wasm_f32x4_extract_lane(wvy, 0);    \
		c1.vely += wasm_f32x4_extract_lane(wvy, 1);    \
		c2.vely += wasm_f32x4_extract_lane(wvy, 2);    \
		c3.vely += wasm_f32x4_extract_lane(wvy, 3);    \
	}

		ci = vp.c00;
		w = vp.w00;
		wvx = wasm_f32x4_mul(w, wasm_f32x4_sub(wasm_f32x4_sub(cvx, vp.gvel00), vp.gvel01));
		wvy = wasm_f32x4_mul(w, wasm_f32x4_sub(wasm_f32x4_sub(cvy, vp.gvel10), vp.gvel11));
		VISIT_CELL();

		ci = vp.c01;
		w = vp.w01;
		wvx = wasm_f32x4_mul(w, wasm_f32x4_sub(cvx, vp.gvel01));
		wvy = wasm_f32x4_mul(w, wasm_f32x4_sub(cvy, vp.gvel11));
		VISIT_CELL();

		ci = vp.c02;
		w = vp.w02;
		wvx = wasm_f32x4_mul(w, wasm_f32x4_sub(wasm_f32x4_add(cvx, vp.gvel00), vp.gvel01));
		wvy = wasm_f32x4_mul(w, wasm_f32x4_sub(wasm_f32x4_add(cvy, vp.gvel10), vp.gvel11));
		VISIT_CELL();

		ci = vp.c10;
		w = vp.w10;
		wvx = wasm_f32x4_mul(w, wasm_f32x4_sub(cvx, vp.gvel00));
		wvy = wasm_f32x4_mul(w, wasm_f32x4_sub(cvy, vp.gvel10));
		VISIT_CELL();

		ci = vp.c11;
		w = vp.w11;
		wvx = wasm_f32x4_mul(w, cvx);
		wvy = wasm_f32x4_mul(w, cvy);
		VISIT_CELL();

		ci = vp.c12;
		w = vp.w12;
		wvx = wasm_f32x4_mul(w, wasm_f32x4_add(cvx, vp.gvel00));
		wvy = wasm_f32x4_mul(w, wasm_f32x4_add(cvy, vp.gvel10));
		VISIT_CELL();

		ci = vp.c20;
		w = vp.w20;
		wvx = wasm_f32x4_mul(w, wasm_f32x4_add(wasm_f32x4_sub(cvx, vp.gvel00), vp.gvel01));
		wvy = wasm_f32x4_mul(w, wasm_f32x4_add(wasm_f32x4_sub(cvy, vp.gvel10), vp.gvel11));
		VISIT_CELL();

		ci = vp.c21;
		w = vp.w21;
		wvx = wasm_f32x4_mul(w, wasm_f32x4_add(cvx, vp.gvel01));
		wvy = wasm_f32x4_mul(w, wasm_f32x4_add(cvy, vp.gvel11));
		VISIT_CELL();

		ci = vp.c22;
		w = vp.w22;
		wvx = wasm_f32x4_mul(w, wasm_f32x4_add(wasm_f32x4_add(cvx, vp.gvel00), vp.gvel01));
		wvy = wasm_f32x4_mul(w, wasm_f32x4_add(wasm_f32x4_add(cvy, vp.gvel10), vp.gvel11));
		VISIT_CELL();

#undef VISIT_CELL
	}

	// normalize aeration
	for (i32 i = 0; i < numC; i++) {
		Cell& c = cs[i];
		if (c.mass > 0) {
			c.aeration /= c.mass;
		}
	}

	// symmetric boundary condition
	for (i32 i = 0; i < gridH; i++) {
		i32 n = gridW - 1;
		i32 off = i * gridW;
		mirror(off, off + 1);
		mirror(off + n, off + n - 1);
	}
	for (i32 j = 0; j < gridW; j++) {
		i32 n = gridH - 1;
		mirror(j, j + gridW);
		mirror(j + n * gridW, j + (n - 1) * gridW);
	}

	// apply pressure
	for (i32 i = 0; i < numP; i += 4) {
		i32 i1 = i;
		i32 i2 = i + 1;
		i32 i3 = i + 2;
		i32 i4 = i + 3;
		Particle& p1 = ps[i1];
		Particle& p2 = ps[i2];
		Particle& p3 = ps[i3];
		Particle& p4 = ps[i4];
		VectorizedParticle& vp = vps[i >> 2];

		v128 density = wasm_f32x4_const_splat(0);
		v128 aeration = wasm_f32x4_const_splat(0);

		Cell& c000 = cs[wasm_i32x4_extract_lane(vp.c00, 0)];
		Cell& c001 = cs[wasm_i32x4_extract_lane(vp.c00, 1)];
		Cell& c002 = cs[wasm_i32x4_extract_lane(vp.c00, 2)];
		Cell& c003 = cs[wasm_i32x4_extract_lane(vp.c00, 3)];
		Cell& c010 = cs[wasm_i32x4_extract_lane(vp.c01, 0)];
		Cell& c011 = cs[wasm_i32x4_extract_lane(vp.c01, 1)];
		Cell& c012 = cs[wasm_i32x4_extract_lane(vp.c01, 2)];
		Cell& c013 = cs[wasm_i32x4_extract_lane(vp.c01, 3)];
		Cell& c020 = cs[wasm_i32x4_extract_lane(vp.c02, 0)];
		Cell& c021 = cs[wasm_i32x4_extract_lane(vp.c02, 1)];
		Cell& c022 = cs[wasm_i32x4_extract_lane(vp.c02, 2)];
		Cell& c023 = cs[wasm_i32x4_extract_lane(vp.c02, 3)];
		Cell& c100 = cs[wasm_i32x4_extract_lane(vp.c10, 0)];
		Cell& c101 = cs[wasm_i32x4_extract_lane(vp.c10, 1)];
		Cell& c102 = cs[wasm_i32x4_extract_lane(vp.c10, 2)];
		Cell& c103 = cs[wasm_i32x4_extract_lane(vp.c10, 3)];
		Cell& c110 = cs[wasm_i32x4_extract_lane(vp.c11, 0)];
		Cell& c111 = cs[wasm_i32x4_extract_lane(vp.c11, 1)];
		Cell& c112 = cs[wasm_i32x4_extract_lane(vp.c11, 2)];
		Cell& c113 = cs[wasm_i32x4_extract_lane(vp.c11, 3)];
		Cell& c120 = cs[wasm_i32x4_extract_lane(vp.c12, 0)];
		Cell& c121 = cs[wasm_i32x4_extract_lane(vp.c12, 1)];
		Cell& c122 = cs[wasm_i32x4_extract_lane(vp.c12, 2)];
		Cell& c123 = cs[wasm_i32x4_extract_lane(vp.c12, 3)];
		Cell& c200 = cs[wasm_i32x4_extract_lane(vp.c20, 0)];
		Cell& c201 = cs[wasm_i32x4_extract_lane(vp.c20, 1)];
		Cell& c202 = cs[wasm_i32x4_extract_lane(vp.c20, 2)];
		Cell& c203 = cs[wasm_i32x4_extract_lane(vp.c20, 3)];
		Cell& c210 = cs[wasm_i32x4_extract_lane(vp.c21, 0)];
		Cell& c211 = cs[wasm_i32x4_extract_lane(vp.c21, 1)];
		Cell& c212 = cs[wasm_i32x4_extract_lane(vp.c21, 2)];
		Cell& c213 = cs[wasm_i32x4_extract_lane(vp.c21, 3)];
		Cell& c220 = cs[wasm_i32x4_extract_lane(vp.c22, 0)];
		Cell& c221 = cs[wasm_i32x4_extract_lane(vp.c22, 1)];
		Cell& c222 = cs[wasm_i32x4_extract_lane(vp.c22, 2)];
		Cell& c223 = cs[wasm_i32x4_extract_lane(vp.c22, 3)];

		density = wasm_f32x4_add(
			density, wasm_f32x4_mul(vp.w00, wasm_f32x4_make(c000.mass, c001.mass, c002.mass, c003.mass)));
		density = wasm_f32x4_add(
			density, wasm_f32x4_mul(vp.w01, wasm_f32x4_make(c010.mass, c011.mass, c012.mass, c013.mass)));
		density = wasm_f32x4_add(
			density, wasm_f32x4_mul(vp.w02, wasm_f32x4_make(c020.mass, c021.mass, c022.mass, c023.mass)));
		density = wasm_f32x4_add(
			density, wasm_f32x4_mul(vp.w10, wasm_f32x4_make(c100.mass, c101.mass, c102.mass, c103.mass)));
		density = wasm_f32x4_add(
			density, wasm_f32x4_mul(vp.w11, wasm_f32x4_make(c110.mass, c111.mass, c112.mass, c113.mass)));
		density = wasm_f32x4_add(
			density, wasm_f32x4_mul(vp.w12, wasm_f32x4_make(c120.mass, c121.mass, c122.mass, c123.mass)));
		density = wasm_f32x4_add(
			density, wasm_f32x4_mul(vp.w20, wasm_f32x4_make(c200.mass, c201.mass, c202.mass, c203.mass)));
		density = wasm_f32x4_add(
			density, wasm_f32x4_mul(vp.w21, wasm_f32x4_make(c210.mass, c211.mass, c212.mass, c213.mass)));
		density = wasm_f32x4_add(
			density, wasm_f32x4_mul(vp.w22, wasm_f32x4_make(c220.mass, c221.mass, c222.mass, c223.mass)));
		aeration = wasm_f32x4_add(aeration,
			wasm_f32x4_mul(
				vp.w00, wasm_f32x4_make(c000.aeration, c001.aeration, c002.aeration, c003.aeration)));
		aeration = wasm_f32x4_add(aeration,
			wasm_f32x4_mul(
				vp.w01, wasm_f32x4_make(c010.aeration, c011.aeration, c012.aeration, c013.aeration)));
		aeration = wasm_f32x4_add(aeration,
			wasm_f32x4_mul(
				vp.w02, wasm_f32x4_make(c020.aeration, c021.aeration, c022.aeration, c023.aeration)));
		aeration = wasm_f32x4_add(aeration,
			wasm_f32x4_mul(
				vp.w10, wasm_f32x4_make(c100.aeration, c101.aeration, c102.aeration, c103.aeration)));
		aeration = wasm_f32x4_add(aeration,
			wasm_f32x4_mul(
				vp.w11, wasm_f32x4_make(c110.aeration, c111.aeration, c112.aeration, c113.aeration)));
		aeration = wasm_f32x4_add(aeration,
			wasm_f32x4_mul(
				vp.w12, wasm_f32x4_make(c120.aeration, c121.aeration, c122.aeration, c123.aeration)));
		aeration = wasm_f32x4_add(aeration,
			wasm_f32x4_mul(
				vp.w20, wasm_f32x4_make(c200.aeration, c201.aeration, c202.aeration, c203.aeration)));
		aeration = wasm_f32x4_add(aeration,
			wasm_f32x4_mul(
				vp.w21, wasm_f32x4_make(c210.aeration, c211.aeration, c212.aeration, c213.aeration)));
		aeration = wasm_f32x4_add(aeration,
			wasm_f32x4_mul(
				vp.w22, wasm_f32x4_make(c220.aeration, c221.aeration, c222.aeration, c223.aeration)));
		vp.density = density;

		p1.dens = wasm_f32x4_extract_lane(density, 0);
		p2.dens = wasm_f32x4_extract_lane(density, 1);
		p3.dens = wasm_f32x4_extract_lane(density, 2);
		p4.dens = wasm_f32x4_extract_lane(density, 3);

		const v128 newAeration = wasm_f32x4_mul(wasm_f32x4_const_splat(AERATION_DAMP),
			wasm_f32x4_add(vp.aeration,
				wasm_f32x4_mul(
					wasm_f32x4_sub(aeration, vp.aeration), wasm_f32x4_const_splat(AERATION_BLUR))));
		vp.aeration = newAeration;

		v128 pressure =
			wasm_f32x4_mul(wasm_f32x4_sub(wasm_f32x4_mul(density, wasm_f32x4_const_splat(INV_DENSITY)),
							   wasm_f32x4_const_splat(1)),
				wasm_f32x4_const_splat(5));
		pressure = wasm_f32x4_max(wasm_f32x4_const_splat(0), pressure);

		v128 volume = wasm_f32x4_div(wasm_f32x4_const_splat(1), density);
		volume = wasm_v128_and(volume, wasm_f32x4_gt(density, wasm_f32x4_const_splat(0)));
		v128 coeff = wasm_f32x4_mul(volume, wasm_f32x4_mul(wasm_f32x4_const_splat(-4), pressure));
		v128 coeffx = wasm_f32x4_mul(coeff, vp.dx);
		v128 coeffy = wasm_f32x4_mul(coeff, vp.dy);

		v128 coeffx0 = wasm_f32x4_sub(coeffx, coeff);
		v128 coeffx1 = coeffx;
		v128 coeffx2 = wasm_f32x4_add(coeffx, coeff);
		v128 coeffy0 = wasm_f32x4_sub(coeffy, coeff);
		v128 coeffy1 = coeffy;
		v128 coeffy2 = wasm_f32x4_add(coeffy, coeff);

		v128 dvx;
		v128 dvy;

		dvx = wasm_f32x4_mul(vp.w00, coeffx0);
		dvy = wasm_f32x4_mul(vp.w00, coeffy0);
		c000.dvelx -= wasm_f32x4_extract_lane(dvx, 0);
		c000.dvely -= wasm_f32x4_extract_lane(dvy, 0);
		c001.dvelx -= wasm_f32x4_extract_lane(dvx, 1);
		c001.dvely -= wasm_f32x4_extract_lane(dvy, 1);
		c002.dvelx -= wasm_f32x4_extract_lane(dvx, 2);
		c002.dvely -= wasm_f32x4_extract_lane(dvy, 2);
		c003.dvelx -= wasm_f32x4_extract_lane(dvx, 3);
		c003.dvely -= wasm_f32x4_extract_lane(dvy, 3);

		dvx = wasm_f32x4_mul(vp.w01, coeffx1);
		dvy = wasm_f32x4_mul(vp.w01, coeffy0);
		c010.dvelx -= wasm_f32x4_extract_lane(dvx, 0);
		c010.dvely -= wasm_f32x4_extract_lane(dvy, 0);
		c011.dvelx -= wasm_f32x4_extract_lane(dvx, 1);
		c011.dvely -= wasm_f32x4_extract_lane(dvy, 1);
		c012.dvelx -= wasm_f32x4_extract_lane(dvx, 2);
		c012.dvely -= wasm_f32x4_extract_lane(dvy, 2);
		c013.dvelx -= wasm_f32x4_extract_lane(dvx, 3);
		c013.dvely -= wasm_f32x4_extract_lane(dvy, 3);

		dvx = wasm_f32x4_mul(vp.w02, coeffx2);
		dvy = wasm_f32x4_mul(vp.w02, coeffy0);
		c020.dvelx -= wasm_f32x4_extract_lane(dvx, 0);
		c020.dvely -= wasm_f32x4_extract_lane(dvy, 0);
		c021.dvelx -= wasm_f32x4_extract_lane(dvx, 1);
		c021.dvely -= wasm_f32x4_extract_lane(dvy, 1);
		c022.dvelx -= wasm_f32x4_extract_lane(dvx, 2);
		c022.dvely -= wasm_f32x4_extract_lane(dvy, 2);
		c023.dvelx -= wasm_f32x4_extract_lane(dvx, 3);
		c023.dvely -= wasm_f32x4_extract_lane(dvy, 3);

		dvx = wasm_f32x4_mul(vp.w10, coeffx0);
		dvy = wasm_f32x4_mul(vp.w10, coeffy1);
		c100.dvelx -= wasm_f32x4_extract_lane(dvx, 0);
		c100.dvely -= wasm_f32x4_extract_lane(dvy, 0);
		c101.dvelx -= wasm_f32x4_extract_lane(dvx, 1);
		c101.dvely -= wasm_f32x4_extract_lane(dvy, 1);
		c102.dvelx -= wasm_f32x4_extract_lane(dvx, 2);
		c102.dvely -= wasm_f32x4_extract_lane(dvy, 2);
		c103.dvelx -= wasm_f32x4_extract_lane(dvx, 3);
		c103.dvely -= wasm_f32x4_extract_lane(dvy, 3);

		dvx = wasm_f32x4_mul(vp.w11, coeffx1);
		dvy = wasm_f32x4_mul(vp.w11, coeffy1);
		c110.dvelx -= wasm_f32x4_extract_lane(dvx, 0);
		c110.dvely -= wasm_f32x4_extract_lane(dvy, 0);
		c111.dvelx -= wasm_f32x4_extract_lane(dvx, 1);
		c111.dvely -= wasm_f32x4_extract_lane(dvy, 1);
		c112.dvelx -= wasm_f32x4_extract_lane(dvx, 2);
		c112.dvely -= wasm_f32x4_extract_lane(dvy, 2);
		c113.dvelx -= wasm_f32x4_extract_lane(dvx, 3);
		c113.dvely -= wasm_f32x4_extract_lane(dvy, 3);

		dvx = wasm_f32x4_mul(vp.w12, coeffx2);
		dvy = wasm_f32x4_mul(vp.w12, coeffy1);
		c120.dvelx -= wasm_f32x4_extract_lane(dvx, 0);
		c120.dvely -= wasm_f32x4_extract_lane(dvy, 0);
		c121.dvelx -= wasm_f32x4_extract_lane(dvx, 1);
		c121.dvely -= wasm_f32x4_extract_lane(dvy, 1);
		c122.dvelx -= wasm_f32x4_extract_lane(dvx, 2);
		c122.dvely -= wasm_f32x4_extract_lane(dvy, 2);
		c123.dvelx -= wasm_f32x4_extract_lane(dvx, 3);
		c123.dvely -= wasm_f32x4_extract_lane(dvy, 3);

		dvx = wasm_f32x4_mul(vp.w20, coeffx0);
		dvy = wasm_f32x4_mul(vp.w20, coeffy2);
		c200.dvelx -= wasm_f32x4_extract_lane(dvx, 0);
		c200.dvely -= wasm_f32x4_extract_lane(dvy, 0);
		c201.dvelx -= wasm_f32x4_extract_lane(dvx, 1);
		c201.dvely -= wasm_f32x4_extract_lane(dvy, 1);
		c202.dvelx -= wasm_f32x4_extract_lane(dvx, 2);
		c202.dvely -= wasm_f32x4_extract_lane(dvy, 2);
		c203.dvelx -= wasm_f32x4_extract_lane(dvx, 3);
		c203.dvely -= wasm_f32x4_extract_lane(dvy, 3);

		dvx = wasm_f32x4_mul(vp.w21, coeffx1);
		dvy = wasm_f32x4_mul(vp.w21, coeffy2);
		c210.dvelx -= wasm_f32x4_extract_lane(dvx, 0);
		c210.dvely -= wasm_f32x4_extract_lane(dvy, 0);
		c211.dvelx -= wasm_f32x4_extract_lane(dvx, 1);
		c211.dvely -= wasm_f32x4_extract_lane(dvy, 1);
		c212.dvelx -= wasm_f32x4_extract_lane(dvx, 2);
		c212.dvely -= wasm_f32x4_extract_lane(dvy, 2);
		c213.dvelx -= wasm_f32x4_extract_lane(dvx, 3);
		c213.dvely -= wasm_f32x4_extract_lane(dvy, 3);

		dvx = wasm_f32x4_mul(vp.w22, coeffx2);
		dvy = wasm_f32x4_mul(vp.w22, coeffy2);
		c220.dvelx -= wasm_f32x4_extract_lane(dvx, 0);
		c220.dvely -= wasm_f32x4_extract_lane(dvy, 0);
		c221.dvelx -= wasm_f32x4_extract_lane(dvx, 1);
		c221.dvely -= wasm_f32x4_extract_lane(dvy, 1);
		c222.dvelx -= wasm_f32x4_extract_lane(dvx, 2);
		c222.dvely -= wasm_f32x4_extract_lane(dvy, 2);
		c223.dvelx -= wasm_f32x4_extract_lane(dvx, 3);
		c223.dvely -= wasm_f32x4_extract_lane(dvy, 3);
	}

	// symmetric boundary condition
	for (i32 i = 0; i < gridH; i++) {
		i32 n = gridW - 1;
		i32 off = i * gridW;
		mirror2(off, off + 1, true, false);
		mirror2(off + n, off + n - 1, true, false);
	}
	for (i32 j = 0; j < gridW; j++) {
		i32 n = gridH - 1;
		mirror2(j, j + gridW, false, true);
		mirror2(j + n * gridW, j + (n - 1) * gridW, false, true);
	}
}

WASM_EXPORT void updateGrid(
	f32 gravityX, f32 gravityY, f32 mouseX, f32 mouseY, f32 dmouseX, f32 dmouseY, f32 radius) {
	v128 gravityXs = wasm_f32x4_splat(gravityX);
	v128 gravityYs = wasm_f32x4_splat(gravityY);
	v128 mouseXs = wasm_f32x4_splat(mouseX);
	v128 mouseYs = wasm_f32x4_splat(mouseY);
	v128 dmouseXs = wasm_f32x4_splat(dmouseX);
	v128 dmouseYs = wasm_f32x4_splat(dmouseY);
	v128 rad2s = wasm_f32x4_splat(radius * radius);
	v128 invRs = wasm_f32x4_splat(1 / radius);

	// momentum to velocity
	{
		for (i32 i = 0; i < gridH; i++) {
			i32 idx = i * gridW;
			for (i32 j = 0; j < gridW; j += 4) {
				Cell& c1 = cs[idx++];
				Cell& c2 = cs[idx++];
				Cell& c3 = cs[idx++];
				Cell& c4 = cs[idx++];
				v128 mass = wasm_f32x4_make(c1.mass, c2.mass, c3.mass, c4.mass);
				v128 mask = wasm_f32x4_gt(mass, wasm_f32x4_const_splat(0));
				v128 invM = wasm_f32x4_div(wasm_f32x4_const_splat(1), mass);
				v128 mx = wasm_f32x4_add(wasm_f32x4_make(c1.velx, c2.velx, c3.velx, c4.velx),
					wasm_f32x4_make(c1.dvelx, c2.dvelx, c3.dvelx, c4.dvelx));
				v128 my = wasm_f32x4_add(wasm_f32x4_make(c1.vely, c2.vely, c3.vely, c4.vely),
					wasm_f32x4_make(c1.dvely, c2.dvely, c3.dvely, c4.dvely));
				v128 vx = wasm_f32x4_add(wasm_f32x4_mul(mx, invM), gravityXs);
				v128 vy = wasm_f32x4_add(wasm_f32x4_mul(my, invM), gravityYs);

				// mouse interaction
				v128 dx = wasm_f32x4_sub(mouseXs, wasm_f32x4_make(j + 0.5, j + 1.5, j + 2.5, j + 3.5));
				v128 dy = wasm_f32x4_sub(mouseYs, wasm_f32x4_make(i + 0.5, i + 0.5, i + 0.5, i + 0.5));
				v128 r2 = wasm_f32x4_add(f32x4_pow2(dx), f32x4_pow2(dy));
				v128 mask2 = wasm_f32x4_lt(r2, rad2s);
				v128 r = wasm_f32x4_sqrt(r2);
				v128 coeff = wasm_f32x4_min(wasm_f32x4_const_splat(1),
					wasm_f32x4_sub(wasm_f32x4_const_splat(2), wasm_f32x4_mul(r, invRs)));
				coeff = wasm_v128_and(coeff, mask2);
				vx = wasm_f32x4_add(vx, wasm_f32x4_mul(coeff, wasm_f32x4_sub(dmouseXs, vx)));
				vy = wasm_f32x4_add(vy, wasm_f32x4_mul(coeff, wasm_f32x4_sub(dmouseYs, vy)));

				vx = wasm_v128_and(vx, mask);
				vy = wasm_v128_and(vy, mask);

				c1.velx = wasm_f32x4_extract_lane(vx, 0);
				c1.vely = wasm_f32x4_extract_lane(vy, 0);
				if (j + 1 < gridW) {
					c2.velx = wasm_f32x4_extract_lane(vx, 1);
					c2.vely = wasm_f32x4_extract_lane(vy, 1);
					if (j + 2 < gridW) {
						c3.velx = wasm_f32x4_extract_lane(vx, 2);
						c3.vely = wasm_f32x4_extract_lane(vy, 2);
						if (j + 3 < gridW) {
							c4.velx = wasm_f32x4_extract_lane(vx, 3);
							c4.vely = wasm_f32x4_extract_lane(vy, 3);
						}
					}
				}
			}
		}
	}

	// boundary condition
	{
		i32 idx = 0;
		for (i32 i = 0; i < gridH; i++) {
			for (i32 j = 0; j < gridW; j++) {
				Cell& c = cs[idx++];
				if (j == 0)
					c.velx = -cs[idx + 1].velx;
				if (j == gridW - 1)
					c.velx = -cs[idx - 1].velx;
				if (i == 0)
					c.vely = -cs[idx + gridW].vely;
				if (i == gridH - 1)
					c.vely = -cs[idx - gridW].vely;
				if (j == 0 && c.velx < 0)
					c.velx *= -1;
				if (j == gridW - 1 && c.velx > 0)
					c.velx *= -1;
				if (i == 0 && c.vely < 0)
					c.vely *= -1;
				if (i == gridH - 1 && c.vely > 0)
					c.vely *= -1;
			}
		}
	}
}

WASM_EXPORT void g2p() {
	const f32 ONE = 1 + 1e-3;
	const v128 minPosX = wasm_f32x4_const_splat(ONE);
	const v128 maxPosX = wasm_f32x4_splat(gridW - ONE);
	const v128 minPosY = wasm_f32x4_const_splat(ONE);
	const v128 maxPosY = wasm_f32x4_splat(gridH - ONE);

	// grid to particle
	for (i32 i = 0; i < numP; i += 4) {
		i32 i1 = i;
		i32 i2 = i + 1;
		i32 i3 = i + 2;
		i32 i4 = i + 3;
		Particle& p1 = ps[i1];
		Particle& p2 = ps[i2];
		Particle& p3 = ps[i3];
		Particle& p4 = ps[i4];
		const VectorizedParticle& vp = vps[i >> 2];

		v128 vx = wasm_f32x4_const_splat(0);
		v128 vy = wasm_f32x4_const_splat(0);
		v128 gv00 = wasm_f32x4_const_splat(0);
		v128 gv01 = wasm_f32x4_const_splat(0);
		v128 gv10 = wasm_f32x4_const_splat(0);
		v128 gv11 = wasm_f32x4_const_splat(0);

		v128 w;
		v128 ci;
		v128 wvx;
		v128 wvy;

#define VISIT_CELL()                                                                  \
	{                                                                                 \
		Cell& c1 = cs[wasm_i32x4_extract_lane(ci, 0)];                                \
		Cell& c2 = cs[wasm_i32x4_extract_lane(ci, 1)];                                \
		Cell& c3 = cs[wasm_i32x4_extract_lane(ci, 2)];                                \
		Cell& c4 = cs[wasm_i32x4_extract_lane(ci, 3)];                                \
		wvx = wasm_f32x4_mul(w, wasm_f32x4_make(c1.velx, c2.velx, c3.velx, c4.velx)); \
		wvy = wasm_f32x4_mul(w, wasm_f32x4_make(c1.vely, c2.vely, c3.vely, c4.vely)); \
	}

		w = vp.w00;
		ci = vp.c00;
		VISIT_CELL();
		vx = wasm_f32x4_add(vx, wvx);
		vy = wasm_f32x4_add(vy, wvy);
		gv00 = wasm_f32x4_sub(gv00, wvx);
		gv01 = wasm_f32x4_sub(gv01, wvx);
		gv10 = wasm_f32x4_sub(gv10, wvy);
		gv11 = wasm_f32x4_sub(gv11, wvy);

		w = vp.w01;
		ci = vp.c01;
		VISIT_CELL();
		vx = wasm_f32x4_add(vx, wvx);
		vy = wasm_f32x4_add(vy, wvy);
		gv01 = wasm_f32x4_sub(gv01, wvx);
		gv11 = wasm_f32x4_sub(gv11, wvy);

		w = vp.w02;
		ci = vp.c02;
		VISIT_CELL();
		vx = wasm_f32x4_add(vx, wvx);
		vy = wasm_f32x4_add(vy, wvy);
		gv00 = wasm_f32x4_add(gv00, wvx);
		gv01 = wasm_f32x4_sub(gv01, wvx);
		gv10 = wasm_f32x4_add(gv10, wvy);
		gv11 = wasm_f32x4_sub(gv11, wvy);

		w = vp.w10;
		ci = vp.c10;
		VISIT_CELL();
		vx = wasm_f32x4_add(vx, wvx);
		vy = wasm_f32x4_add(vy, wvy);
		gv00 = wasm_f32x4_sub(gv00, wvx);
		gv10 = wasm_f32x4_sub(gv10, wvy);

		w = vp.w11;
		ci = vp.c11;
		VISIT_CELL();
		vx = wasm_f32x4_add(vx, wvx);
		vy = wasm_f32x4_add(vy, wvy);

		w = vp.w12;
		ci = vp.c12;
		VISIT_CELL();
		vx = wasm_f32x4_add(vx, wvx);
		vy = wasm_f32x4_add(vy, wvy);
		gv00 = wasm_f32x4_add(gv00, wvx);
		gv10 = wasm_f32x4_add(gv10, wvy);

		w = vp.w20;
		ci = vp.c20;
		VISIT_CELL();
		vx = wasm_f32x4_add(vx, wvx);
		vy = wasm_f32x4_add(vy, wvy);
		gv00 = wasm_f32x4_sub(gv00, wvx);
		gv01 = wasm_f32x4_add(gv01, wvx);
		gv10 = wasm_f32x4_sub(gv10, wvy);
		gv11 = wasm_f32x4_add(gv11, wvy);

		w = vp.w21;
		ci = vp.c21;
		VISIT_CELL();
		vx = wasm_f32x4_add(vx, wvx);
		vy = wasm_f32x4_add(vy, wvy);
		gv01 = wasm_f32x4_add(gv01, wvx);
		gv11 = wasm_f32x4_add(gv11, wvy);

		w = vp.w22;
		ci = vp.c22;
		VISIT_CELL();
		vx = wasm_f32x4_add(vx, wvx);
		vy = wasm_f32x4_add(vy, wvy);
		gv00 = wasm_f32x4_add(gv00, wvx);
		gv01 = wasm_f32x4_add(gv01, wvx);
		gv10 = wasm_f32x4_add(gv10, wvy);
		gv11 = wasm_f32x4_add(gv11, wvy);

		gv00 = wasm_f32x4_mul(wasm_f32x4_const_splat(4), wasm_f32x4_add(gv00, wasm_f32x4_mul(vx, vp.dx)));
		gv01 = wasm_f32x4_mul(wasm_f32x4_const_splat(4), wasm_f32x4_add(gv01, wasm_f32x4_mul(vx, vp.dy)));
		gv10 = wasm_f32x4_mul(wasm_f32x4_const_splat(4), wasm_f32x4_add(gv10, wasm_f32x4_mul(vy, vp.dx)));
		gv11 = wasm_f32x4_mul(wasm_f32x4_const_splat(4), wasm_f32x4_add(gv11, wasm_f32x4_mul(vy, vp.dy)));

		v128 nposx = wasm_f32x4_min(wasm_f32x4_max(wasm_f32x4_add(vp.posx, vx), minPosX), maxPosX);
		v128 nposy = wasm_f32x4_min(wasm_f32x4_max(wasm_f32x4_add(vp.posy, vy), minPosY), maxPosY);
		v128 nvelx = wasm_f32x4_sub(nposx, vp.posx);
		v128 nvely = wasm_f32x4_sub(nposy, vp.posy);

		v128 accx = wasm_f32x4_sub(nvelx, vp.velx);
		v128 accy = wasm_f32x4_sub(nvely, vp.vely);
		v128 densityRatio = wasm_f32x4_mul(vp.density, wasm_f32x4_const_splat(INV_DENSITY));
		v128 accLen = wasm_f32x4_sqrt(wasm_f32x4_add(f32x4_pow2(accx), f32x4_pow2(accy)));
		v128 aerationScale = wasm_f32x4_mul(
			wasm_f32x4_sub(wasm_f32x4_const_splat(1),
				wasm_f32x4_mul(densityRatio, wasm_f32x4_const_splat(1.0 / AERATION_THRESHOLD))),
			wasm_f32x4_const_splat(AERATION_COEFF));
		v128 aerationDelta = wasm_f32x4_max(wasm_f32x4_const_splat(0), wasm_f32x4_mul(accLen, aerationScale));
		v128 newAeration =
			wasm_f32x4_min(wasm_f32x4_const_splat(1), wasm_f32x4_add(vp.aeration, aerationDelta));

		p1.aeration = wasm_f32x4_extract_lane(newAeration, 0);
		p2.aeration = wasm_f32x4_extract_lane(newAeration, 1);
		p3.aeration = wasm_f32x4_extract_lane(newAeration, 2);
		p4.aeration = wasm_f32x4_extract_lane(newAeration, 3);
		p1.posx = wasm_f32x4_extract_lane(nposx, 0);
		p2.posx = wasm_f32x4_extract_lane(nposx, 1);
		p3.posx = wasm_f32x4_extract_lane(nposx, 2);
		p4.posx = wasm_f32x4_extract_lane(nposx, 3);
		p1.posy = wasm_f32x4_extract_lane(nposy, 0);
		p2.posy = wasm_f32x4_extract_lane(nposy, 1);
		p3.posy = wasm_f32x4_extract_lane(nposy, 2);
		p4.posy = wasm_f32x4_extract_lane(nposy, 3);
		p1.velx = wasm_f32x4_extract_lane(nvelx, 0);
		p2.velx = wasm_f32x4_extract_lane(nvelx, 1);
		p3.velx = wasm_f32x4_extract_lane(nvelx, 2);
		p4.velx = wasm_f32x4_extract_lane(nvelx, 3);
		p1.vely = wasm_f32x4_extract_lane(nvely, 0);
		p2.vely = wasm_f32x4_extract_lane(nvely, 1);
		p3.vely = wasm_f32x4_extract_lane(nvely, 2);
		p4.vely = wasm_f32x4_extract_lane(nvely, 3);
		p1.gvel00 = wasm_f32x4_extract_lane(gv00, 0);
		p2.gvel00 = wasm_f32x4_extract_lane(gv00, 1);
		p3.gvel00 = wasm_f32x4_extract_lane(gv00, 2);
		p4.gvel00 = wasm_f32x4_extract_lane(gv00, 3);
		p1.gvel01 = wasm_f32x4_extract_lane(gv01, 0);
		p2.gvel01 = wasm_f32x4_extract_lane(gv01, 1);
		p3.gvel01 = wasm_f32x4_extract_lane(gv01, 2);
		p4.gvel01 = wasm_f32x4_extract_lane(gv01, 3);
		p1.gvel10 = wasm_f32x4_extract_lane(gv10, 0);
		p2.gvel10 = wasm_f32x4_extract_lane(gv10, 1);
		p3.gvel10 = wasm_f32x4_extract_lane(gv10, 2);
		p4.gvel10 = wasm_f32x4_extract_lane(gv10, 3);
		p1.gvel11 = wasm_f32x4_extract_lane(gv11, 0);
		p2.gvel11 = wasm_f32x4_extract_lane(gv11, 1);
		p3.gvel11 = wasm_f32x4_extract_lane(gv11, 2);
		p4.gvel11 = wasm_f32x4_extract_lane(gv11, 3);

#undef VISIT_CELL
	}
}
