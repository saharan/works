#include <emscripten.h>
#include <stdint.h>
#include <wasm_simd128.h>

#define WASM_EXPORT extern "C" EMSCRIPTEN_KEEPALIVE

using i32 = int32_t;
using u32 = uint32_t;
using i64 = int64_t;
using u64 = uint64_t;
using f32 = float;
using f64 = double;
using v128 = v128_t;

inline i32 ptr(void* p) {
	return (i32) (size_t) p;
}
