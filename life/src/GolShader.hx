import hgsl.Global.*;
import hgsl.ShaderMain;
import hgsl.ShaderStruct;
import hgsl.Types;
import pot.graphics.gl.shader.Matrix;

private class Node extends ShaderStruct {
	var children:Array<Int, 4>;
	var pop:Int;
	var level:Int;
}

class GolShader extends ShaderMain {
	final GRAPH_TEX_LOG_SIZE = ivec2(10, 11);
	final TILES_TEX_LOG_SIZE = ivec2(7, 7);
	final GRAPH_TEX_SIZE = ivec2(1) << GRAPH_TEX_LOG_SIZE;
	final TILES_TEX_SIZE = ivec2(1) << TILES_TEX_LOG_SIZE;
	final NUM_NODES_FOR_EACH_LEVEL = [0, 0, 0, 43566, 58879, 89218, 134733, 255330, 428144, 477174];
	final OFFSET_FOR_EACH_LEVEL = [0, 0, 0, 0, 43566, 102445, 191663, 326396, 581726, 1009870];

	@attribute(0) var aPosition:Vec4;
	@attribute(1) var aColor:Vec4;
	@attribute(2) var aNormal:Vec3;
	@attribute(3) var aTexCoord:Vec2;

	@uniform var resolution:Vec2;
	@uniform var translation:Vec2;
	@uniform var matrix:Matrix;
	@uniform var graph:USampler2D;
	@uniform var tiles:USampler2D;
	@uniform var topTiles:USampler2D;
	@uniform var camera:Vec4;
	@uniform var rawCamera:Vec4;
	@uniform var preRendering:Bool;

	@uniform var prerenderedTopTiles:Sampler2D;
	@uniform var transition:Float;
	@uniform var heat:Float;

	@varying var vPosition:Vec2;
	@varying var vRawPosition:Vec2;
	@varying var vTexCoord:Vec2;

	@color var oColor:Vec4;

	function vertex():Void {
		gl_Position = matrix.transform * aPosition;
		{
			final mins = camera.xy;
			final maxs = camera.zw;
			final pos = vec2(aTexCoord.x, 1 - aTexCoord.y);
			vPosition = mix(mins, maxs, pos);
		}
		{
			final mins = rawCamera.xy;
			final maxs = rawCamera.zw;
			final pos = vec2(aTexCoord.x, 1 - aTexCoord.y);
			vRawPosition = mix(mins, maxs, pos);
		}
		vTexCoord = aTexCoord;
	}

	function parseNode(pixel:UVec4, level:Int):Node {
		final ir = pixel.r;
		final ig = pixel.g;
		final ib = pixel.b;
		final ia = pixel.a;
		final popLow = ir >> 24;
		final popHigh = ig >> 24;
		final c1 = int(ir & 0xffffff);
		final c2 = int(ig & 0xffffff);
		final c3 = int(ib);
		final c4 = int(ia);
		final pop = int(popLow | popHigh << 8);
		final node = {
			children: [c1, c2, c3, c4],
			pop: pop,
			level: level,
		}
		return node;
	}

	function getNode(level:Int, index:Int):Node {
		final pixelIndex = index + OFFSET_FOR_EACH_LEVEL[level];
		final pixel = fetchPixelIndex(graph, GRAPH_TEX_SIZE, GRAPH_TEX_LOG_SIZE, pixelIndex);
		return parseNode(pixel, level);
	}

	function sampleBitLevel9(index:Int, pos:IVec2):Int {
		var level = 9;
		for (iter in 0...7) {
			final size = 1 << (level - 1);
			final node = getNode(level, index);
			if (pos.y < size) {
				if (pos.x < size) {
					index = node.children[0];
				} else {
					index = node.children[1];
					pos.x -= size;
				}
			} else {
				pos.y -= size;
				if (pos.x < size) {
					index = node.children[2];
				} else {
					index = node.children[3];
					pos.x -= size;
				}
			}
			level--;
		}
		final bitIndex = 15 ^ (pos.y << 2 | pos.x);
		return index >> bitIndex & 1;
	}

	function popcount16(i:Int):Int {
		i = (i & 0x5555) + (i >> 1 & 0x5555);
		i = (i & 0x3333) + (i >> 2 & 0x3333);
		i = (i & 0x0f0f) + (i >> 4 & 0x0f0f);
		return (i & 0x00ff) + (i >> 8);
	}

	function popcount4(i:Int):Int {
		i = (i & 5) + (i >> 1 & 5);
		return (i & 3) + (i >> 2);
	}

	function linearstep(edge0:Float, edge1:Float, t:Float):Float {
		return clamp((t - edge0) / (edge1 - edge0), 0, 1);
	}

	function correctDensity(rawDensity:Float, level:Int, cellState:Float):Float {
		final zero = 0.002;
		final one = 0.005;
		final t = smoothstep(0.5, 1, level / 9.0);
		final v1 = linearstep(zero, one, rawDensity);
		final v2 = linearstep(pow(zero, cellState * 2), pow(one, cellState * 2), rawDensity);
		return mix(v1, v2, t);
	}

	function sampleBitLevel9(index:Int, pos:IVec2, res:Float, cellState:Float):Float {
		var level = 9;
		var invArea = 1.0 / (512 * 512);
		var prevValue = 0.0;
		final pixelSize = 1.0;
		for (iter in 0...7) {
			final size = 1 << (level - 1);
			final node = getNode(level, index);
			final density = node.pop * invArea;
			final value = correctDensity(density, level, cellState);
			if (iter == 0)
				prevValue = value;
			if (res <= pixelSize) {
				final t = (pixelSize - res) / res;
				return value + t * (prevValue - value);
			}
			prevValue = value;
			if (pos.y < size) {
				if (pos.x < size) {
					index = node.children[0];
				} else {
					index = node.children[1];
					pos.x -= size;
				}
			} else {
				pos.y -= size;
				if (pos.x < size) {
					index = node.children[2];
				} else {
					index = node.children[3];
					pos.x -= size;
				}
			}
			level--;
			res *= 0.5;
			invArea *= 4;
		}
		// 4x4
		{
			final density = popcount16(index) * invArea;
			final value = correctDensity(density, level, cellState);
			if (res <= pixelSize) {
				final t = (pixelSize - res) / res;
				return value + t * (prevValue - value);
			}
			prevValue = value;
		}
		if (pos.y < 2) {
			if (pos.x < 2) {
				index = (index >> 0xa & 3) | ((index >> 0xe & 3) << 2);
			} else {
				index = (index >> 0x8 & 3) | ((index >> 0xc & 3) << 2);
				pos.x -= 2;
			}
		} else {
			pos.y -= 2;
			if (pos.x < 2) {
				index = (index >> 0x2 & 3) | ((index >> 0x6 & 3) << 2);
			} else {
				index = (index >> 0x0 & 3) | ((index >> 0x4 & 3) << 2);
				pos.x -= 2;
			}
		}
		res *= 0.5;
		invArea *= 4;
		// 2x2
		{
			final density = popcount4(index) * invArea;
			final value = correctDensity(density, level, cellState);
			if (res <= pixelSize) {
				final t = (pixelSize - res) / res;
				return value + t * (prevValue - value);
			}
			prevValue = value;
		}
		res *= 0.5;
		// 1x1
		final value = float(index >> (3 ^ (pos.y << 1) ^ pos.x) & 1);
		if (res <= pixelSize) {
			final t = (pixelSize - res) / res;
			return value + t * (prevValue - value);
		}
		return value;
	}

	function getTileNodeIndex(frameIndexId:Int, pos:IVec2, pattern:Int):Int {
		final offset = 1024 * 16 * frameIndexId;
		final rawIndex = offset | ((pos.y << 2 | pos.x) << 10) | pattern;
		final pixelIndex = rawIndex >> 2;
		final pixelOffset = rawIndex & 3;
		return int(fetchPixelIndex(tiles, TILES_TEX_SIZE, TILES_TEX_LOG_SIZE, pixelIndex)[pixelOffset]);
	}

	function fetchPixelIndex(sampler:USampler2D, size:IVec2, logSize:IVec2, index:Int):UVec4 {
		return texelFetch(sampler, ivec2(index & (size.x - 1), index >> logSize.x), 0);
	}

	function fetchTile(index:IVec2, channel:Int):Int {
		if (index.x < 0 || index.x >= 16 || index.y < 0 || index.y >= 16)
			return -1;
		return int(texelFetch(topTiles, index, 0)[channel]);
	}

	function samplePixel(pixCoord:IVec2, offset:IVec2):IVec2 {
		pixCoord += offset;
		pixCoord = ivec2(pixCoord.x, textureSize(prerenderedTopTiles, 0).y - 1 - pixCoord.y);
		return ivec2(texelFetch(prerenderedTopTiles, pixCoord, 0).xy);
	}

	function samplePattern(pixCoord:IVec2):Int {
		final center = samplePixel(pixCoord, ivec2(0));
		var bit = samplePixel(pixCoord, ivec2(-1, -1)).x;
		bit |= samplePixel(pixCoord, ivec2(0, -1)).x << 1;
		bit |= samplePixel(pixCoord, ivec2(1, -1)).x << 2;
		bit |= samplePixel(pixCoord, ivec2(-1, 0)).x << 3;
		bit |= center.x << 4;
		bit |= samplePixel(pixCoord, ivec2(1, 0)).x << 5;
		bit |= samplePixel(pixCoord, ivec2(-1, 1)).x << 6;
		bit |= samplePixel(pixCoord, ivec2(0, 1)).x << 7;
		bit |= samplePixel(pixCoord, ivec2(1, 1)).x << 8;
		bit |= center.y << 9;
		bit ^= (bit >> 4 & 1) << 9;
		return bit;
	}

	function colorAt(pos:Vec2):Vec3 {
		final twopi = 2 * 3.141592653589793;
		final p = fract(pos) * 2 - 1;
		final s = sign(p) * pow(abs(p), 2 - (p * p).yx) * 0.5;
		final ang = 1 + dot(s, vec2(1)) * twopi;
		final amp = 0.35 - cos(ang) * 0.05;
		return (1 - amp) + amp * cos(ang + vec3(twopi / 3, -twopi / 3, 0));
	}

	function fragment():Void {
		final outerRes = resolution.x / (camera.z - camera.x);
		final innerRes = outerRes / 2048.0;

		final tileCoord = vPosition * 4;

		if (preRendering) {
			final tileIndex = ivec2(floor(tileCoord));
			final insideTileIndex = ivec2(fract(tileCoord) * 512);
			final index = fetchTile(tileIndex, 0);
			final pindex = fetchTile(tileIndex, 1);
			final pop = sampleBitLevel9(index, insideTileIndex);
			final ppop = sampleBitLevel9(pindex, insideTileIndex);
			oColor = vec4(pop, ppop, 0, 1);
		} else {
			final outerPattern = samplePattern(ivec2(tileCoord * 512));
			final insidePixelCoord = fract(tileCoord * 512) * 4;
			final innerTileIndex = ivec2(insidePixelCoord);
			final cellState = mix((outerPattern >> 9 ^ outerPattern >> 4) & 1, outerPattern >> 4 & 1, transition);

			final level9Index = getTileNodeIndex(0, innerTileIndex, outerPattern);
			final pop = sampleBitLevel9(level9Index, ivec2(fract(insidePixelCoord) * 512), innerRes * 0.25, cellState);
			final color1 = colorAt(fract(vRawPosition));
			final color2 = colorAt(fract(vRawPosition * 2048));
			final colorCoeff = pow(linearstep(log(2), log(4096.0), log(innerRes)), 2);
			final color = mix(color1, color2, colorCoeff);
			final heatColor = heat > 0 ? vec3(heat, heat * 0.3, heat * -0.1) : vec3(heat * 0.2, heat * -0.2, heat * -1);
			final colorWithHeat = (color / max(color.x, max(color.y, color.z)) + heatColor) / (heat >= 0 ? 1 + heat : 1 - heat * 4);

			oColor = vec4(colorWithHeat * pop, 1);
		}
	}
}
