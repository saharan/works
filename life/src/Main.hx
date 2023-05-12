import Graph.Node;
import js.Browser;
import js.lib.Uint32Array;
import muun.la.Vec2;
import muun.la.Vec3;
import pot.core.App;
import pot.graphics.bitmap.Bitmap;
import pot.graphics.bitmap.BitmapGraphics;
import pot.graphics.gl.FrameBuffer;
import pot.graphics.gl.Graphics;
import pot.graphics.gl.Shader;
import pot.graphics.gl.Texture;
import pot.util.ImageLoader;

using Lambda;

class Main extends App {
	public static inline final PERIOD = 35328;
	public static inline final TRANSITION_START = 4100;
	public static inline final TRANSITION_END = 7400;

	var g:Graphics;
	final offset:Vec2 = Vec2.zero;
	final scale:Vec2 = Vec2.zero;
	var graph:Graph;
	var frames:Frames;
	var golShader:Shader;
	var sampler:Sampler;
	var universe:Universe;

	static inline final GRAPH_TEX_WIDTH = 1024;
	static inline final GRAPH_TEX_HEIGHT = 2048;
	static inline final TILES_TEX_WIDTH = 128;
	static inline final TILES_TEX_HEIGHT = 128;

	var graphTexture:Texture;
	var tilesTexture:Texture;
	var topTilesTexture:Texture;
	var prerenderedTopTilesTexture:Texture;
	var prerenderedTopTilesTextureFB:FrameBuffer;
	final tilesData:Uint32Array = new Uint32Array(TILES_TEX_WIDTH * TILES_TEX_HEIGHT * 4);
	final topTilesData:Uint32Array = new Uint32Array(16 * 16 * 4);
	var controller:Controller;

	final text = Browser.document.getElementById("text");

	var barW:Float = 200;
	final barH:Float = 30;
	final barH2:Float = 5;
	final barW2:Float = 10;
	final barPad:Float = 4;
	var barT:Float = 0.3;
	var barX:Float = 50;
	var barY:Float = 50;
	var heat:Float = 0;

	var speedText:Bitmap;
	var speedTextTexture:Texture;
	var speedTextG:BitmapGraphics;

	var speedTextFocusAlpha:Float = 0.3;

	override function setup():Void {
		pot.frameRate(Fixed(60));

		g = new Graphics(canvas);
		g.init2D();

		speedText = new Bitmap(256, 32);
		speedTextG = speedText.getGraphics();
		speedTextTexture = g.loadBitmap(speedText);

		ImageLoader.loadImages(["graph.png", "anim.png", "loc.png"], imgs -> {
			final graphImg = imgs[0];
			final animImg = imgs[1];
			final locImg = imgs[2];
			graphImg.loadPixels();
			animImg.loadPixels();
			locImg.loadPixels();
			final decoder = new Decoder();
			decoder.decodeGraph(cast graphImg.pixels);
			decoder.decodeAnim(cast animImg.pixels);
			decoder.decodeLocation(cast locImg.pixels);
			graph = decoder.graph;
			frames = decoder.frames;
			sampler = new Sampler(graph, frames);
			universe = new Universe(sampler, pot.width);
			controller = new Controller(universe, input);
			initTextures();
			initShaders();
			init();
			final cover = Browser.document.getElementById("cover");
			cover.parentElement.removeChild(cover);
			pot.start();
		});
	}

	function samplePatterns():Void {
		final patterns = [];
		final data = {
			final data = [for (i in 0...1024) {i: i, a: []}];
			for (i in 0...100000) {
				while (true) {
					final time = Std.random(PERIOD);
					final x = Std.random(2046) + 1;
					final y = Std.random(2046) + 1;
					final pattern = Std.random(511) + 1 | Std.random(2) << 9;
					final res = sampler.samplePattern(time, x, y, [null, null, null, null, pattern, null, null, null, null]);
					if (res & 511 != 0) {
						data[res].a.push([pattern, x, y, time]);
						break;
					}
				}
			}
			data.sort((a, b) -> b.a.length - a.a.length);
			for (i in 0...64) {
				trace(data[i].i + " " + data[i].a.length);
			}
			data.splice(64, data.length);
			data.sort((a, b) -> a.i - b.i);
			for (data in data) {
				patterns.push(data.i);
			}
			[for (i in 0...1024) data.exists(d -> d.i == i) ? [] : null];
		}

		for (i in 0...64) {
			trace("trying pattern " + patterns[i] + " (" + (i + 1) + "/" + 64 + ")...");
			var count = 0;
			while (count < 64) {
				final time = Std.random(PERIOD);
				final x = Std.random(2046) + 1;
				final y = Std.random(2046) + 1;
				final pattern = patterns[i];
				final res = sampler.samplePattern(time, x, y, [null, null, null, null, pattern, null, null, null, null]);
				if (data[res] != null && data[res].length == i) {
					data[res].push([x, y, time]);
					count++;
				}
			}
		}
		trace(patterns.join("\n"));
		trace(data.filter(d -> d != null).flatten().map(d -> d.join(" ")).join("\n"));
	}

	function addNodePixels(pixels:Array<Int>, node:Node):Void {
		final c1 = node.children[0]; // 19 bits
		final c2 = node.children[1]; // 19 bits
		final c3 = node.children[2]; // 19 bits
		final c4 = node.children[3]; // 19 bits
		final pop = node.pop; // 13 bits
		final popLow = pop & 0xff;
		final popHigh = pop >> 8 & 0xff;
		final ir = c1 | (popLow << 24);
		final ig = c2 | (popHigh << 24);
		final ib = c3;
		final ia = c4;
		pixels.push(ir);
		pixels.push(ig);
		pixels.push(ib);
		pixels.push(ia);
	}

	function createGraphTexturePixels():Array<Int> {
		final res = [];
		for (nodesInLevel in graph.nodes) {
			for (node in nodesInLevel) {
				addNodePixels(res, node);
			}
		}
		trace("len: " + res.length);
		final MAX_INTS = GRAPH_TEX_WIDTH * GRAPH_TEX_HEIGHT * 4;
		assert(res.length <= MAX_INTS);
		while (res.length < MAX_INTS) {
			res.push(0);
		}
		return res;
	}

	function updateAnimData(frameIndices:Array<Int>):Void {
		assert(frameIndices.length == 4);
		var i = 0;
		for (index in frameIndices) {
			for (tile in frames.restoreFrame(index)) {
				for (nodeIndex in tile) {
					tilesData[i++] = nodeIndex;
				}
			}
		}
		tilesTexture.upload(0, 0, TILES_TEX_WIDTH, TILES_TEX_HEIGHT, tilesData, false);
	}

	function updateTopTiles(tiles:Array<Array<Array<Int>>>):Void {
		final h = tiles.length;
		final w = tiles[0].length;
		assert(w <= 16 && h <= 16);
		var index = 0;
		for (i in 0...16) {
			for (j in 0...16) {
				topTilesData[index++] = i < h && j < w ? tiles[i][j][0] : 0;
				topTilesData[index++] = i < h && j < w ? tiles[i][j][1] : 0;
				topTilesData[index++] = 0;
				topTilesData[index++] = 0;
			}
		}
		topTilesTexture.upload(0, 0, 16, 16, topTilesData, false);
		if (prerenderedTopTilesTexture == null || prerenderedTopTilesTexture.width < w * 512 || prerenderedTopTilesTexture.height < h * 512) {
			if (prerenderedTopTilesTexture != null) {
				prerenderedTopTilesTexture.dispose();
				prerenderedTopTilesTextureFB.dispose();
			}
			prerenderedTopTilesTexture = g.createTexture(w * 512, h * 512);
			prerenderedTopTilesTexture.filter(Nearest);
			prerenderedTopTilesTextureFB = g.createFrameBuffer(prerenderedTopTilesTexture);
		}

		g.defaultUniformMap.set(GolShader.uniforms.camera.name, Vec4(0, 0, w / 4, h / 4));
		g.defaultUniformMap.set(GolShader.uniforms.preRendering.name, Bool(true));
		g.defaultUniformMap.set(GolShader.uniforms.prerenderedTopTiles.name, Sampler(null));
		g.renderingTo(prerenderedTopTilesTextureFB, () -> {
			g.viewport(0, 0, w * 512, h * 512);
			g.inScene(() -> {
				g.shader(golShader);
				g.fullScreenRect();
				g.resetShader();
			});
			g.resetViewport();
		});
		g.defaultUniformMap.set(GolShader.uniforms.preRendering.name, Bool(false));
		g.defaultUniformMap.set(GolShader.uniforms.prerenderedTopTiles.name, Sampler(prerenderedTopTilesTexture));
	}

	function initTextures():Void {
		graphTexture = g.createTexture(GRAPH_TEX_WIDTH, GRAPH_TEX_HEIGHT, UInt32);
		graphTexture.upload(0, 0, GRAPH_TEX_WIDTH, GRAPH_TEX_HEIGHT, new Uint32Array(createGraphTexturePixels()), false);
		g.defaultUniformMap.set(GolShader.uniforms.graph.name, Sampler(graphTexture));

		tilesTexture = g.createTexture(TILES_TEX_WIDTH, TILES_TEX_HEIGHT, UInt32);
		g.defaultUniformMap.set(GolShader.uniforms.tiles.name, Sampler(tilesTexture));
		updateAnimData([0, 0, 0, 0]);

		topTilesTexture = g.createTexture(16, 16, UInt32);
		g.defaultUniformMap.set(GolShader.uniforms.topTiles.name, Sampler(topTilesTexture));

		assert(GolShader.consts.GRAPH_TEX_SIZE[0] == GRAPH_TEX_WIDTH);
		assert(GolShader.consts.GRAPH_TEX_SIZE[1] == GRAPH_TEX_HEIGHT);
		assert(GolShader.consts.TILES_TEX_SIZE[0] == TILES_TEX_WIDTH);
		assert(GolShader.consts.TILES_TEX_SIZE[1] == TILES_TEX_HEIGHT);
	}

	function initShaders():Void {
		golShader = g.createShader(GolShader.source.vertex, GolShader.source.fragment);
	}

	function init():Void {
		universe.scaleCamera(pot.width / 8);
		universe.normalizeZoom(pot.width);
	}

	override function update():Void {
		barW = min(500, pot.width * 0.5);
		barX = pot.width * 0.5 - barW * 0.5 - barPad;
		barY = pot.height - barH - barPad * 2 - 30;
		controller.setBar(barX, barY, barW, barH, barPad);

		controller.update(pot.width, pot.height, heat);

		canvas.style.cursor = controller.barFocus ? "pointer" : null;
		barT = controller.barT;

		speedTextFocusAlpha += ((controller.barFocus ? 1 : 0.3) - speedTextFocusAlpha) * 0.2;

		final minStep = 1e-4;
		final coeff = 16 / 0.7;
		final speed = Math.pow(2, (barT - 0.3) * coeff) + mix(minStep - Math.pow(2, -0.3 * coeff), 0, clamp(barT / 0.3, 0, 1));

		final base = speed < 1 ? 10000 : speed < 10 ? 1000 : speed < 100 ? 100 : speed < 1000 ? 10 : 1;
		final roundedSpeed = Math.round(speed * base) / base;
		var speedStr = "x" + roundedSpeed;
		final expectedLength = roundedSpeed < 1 ? 7 : 6;
		if (roundedSpeed < 1000 && speedStr.length < expectedLength) {
			if (speedStr.indexOf(".") == -1)
				speedStr += ".";
			while (speedStr.length < expectedLength)
				speedStr += "0";
		}
		speedTextG.font("Courier New", 20, Bold, Monospace);
		speedTextG.textAlign(Center);
		speedTextG.textBaseline(Middle);
		speedTextG.clear(0, 0, 0, 0);
		speedTextG.strokeWidth(8);
		speedTextG.strokeColor(0, 0, 0, 0.5);
		speedTextG.strokeText(speedStr, speedText.width * 0.5, speedText.height * 0.5);
		speedTextG.fillColor(1, 1, 1);
		speedTextG.fillText(speedStr, speedText.width * 0.5, speedText.height * 0.5);
		g.loadBitmapTo(speedTextTexture, speedText);

		universe.step(speed);

		heat = Math.log(speed) * 0.05;
		g.defaultUniformMap.set(GolShader.uniforms.heat.name, Float(heat));

		// if (input.mouse.dright == 1)
		// 	trace(universe.refLevel.toString(true));
	}

	override function draw():Void {
		g.defaultUniformMap.set(GolShader.uniforms.translation.name, Vec2(input.mouse.x - pot.width * 0.5,
			input.mouse.y - pot.height * 0.5));
		g.defaultUniformMap.set(GolShader.uniforms.resolution.name, Vec2(pot.width, pot.height));

		universe.setCameraAspect(pot.width / pot.height);
		universe.normalizeZoom(pot.width);
		final timeFract = universe.getTimeFract();
		final transition = clamp((timeFract - TRANSITION_START) / (TRANSITION_END - TRANSITION_START), 0, 1);
		updateAnimData([timeFract, 0, 0, 0]);

		final viewInfo = universe.getViewInfo(pot.width, pot.height);
		updateTopTiles(viewInfo.visibleTiles);
		final bounds = viewInfo.cameraBounds;
		final rawBounds = viewInfo.rawCameraBounds;
		g.defaultUniformMap.set(GolShader.uniforms.camera.name, Vec4(bounds[0], bounds[1], bounds[2], bounds[3]));
		g.defaultUniformMap.set(GolShader.uniforms.rawCamera.name, Vec4(rawBounds[0], rawBounds[1], rawBounds[2], rawBounds[3]));
		g.defaultUniformMap.set(GolShader.uniforms.transition.name, Float(transition));

		g.screen(pot.width, pot.height);
		g.inScene(() -> {
			final bgColor = Vec3.zero;
			if (heat < 0)
				bgColor <<= Vec3.of(0, -heat * 0.1, -heat * 0.4);
			if (heat > 0)
				bgColor <<= Vec3.of(heat * 0.4, heat * 0.1, 0);
			g.color(bgColor, 1 / (1 + (heat > 0 ? heat * heat * 4 : -heat * 4)));
			g.fullScreenRect();

			g.blend(Add);
			g.shader(golShader);
			g.fullScreenRect();
			g.resetShader();
			g.blend();

			g.color(0, 0, 0, 0.4);
			g.rect(barX, barY, barW + barPad * 2, barH + barPad * 2);
			g.color(0.7, 0.7, 0.7);
			g.rect(barX + barPad, barY + barPad + barH * 0.5 - barH2 * 0.5, barW * barT, barH2);
			g.color(0.5, 0.5, 0.5);
			g.rect(barX + barPad + 0.3 * barW - barW2 * 0.25, barY + barPad, barW2 * 0.5, barH);
			g.color(1, 1, 1);
			g.rect(barX + barPad + barT * (barW - barW2), barY + barPad, barW2, barH);

			g.texture(speedTextTexture);
			g.color(1, speedTextFocusAlpha);
			g.rect(barX + barPad + barT * barW - speedTextTexture.width * 0.5, barY - speedTextTexture.height, speedTextTexture.width,
				speedTextTexture.height);
			g.noTexture();
		});
	}

	static function main():Void {
		new Main(cast Browser.document.getElementById("canvas"));
	}
}
