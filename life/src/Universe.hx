import muun.la.Vec4;

class Universe {
	public var refLevel:Level;

	final sampler:Sampler;

	var camX:Float;
	var camY:Float;
	var camHW:Float;
	var camHH:Float;
	var camAspect:Float;
	var timeFract:Float;

	public function new(sampler:Sampler, aspect:Float) {
		this.sampler = sampler;
		refLevel = Level.generateRandomLevel(sampler);
		camX = 0.5;
		camY = 0.5;
		camHW = 0.5;
		camHH = camHW / aspect;
		camAspect = aspect;
		timeFract = 0;
	}

	public function cameraWidth():Float {
		return 2 * camHW;
	}

	public function cameraHeight():Float {
		return 2 * camHH;
	}

	public function setCameraAspect(aspect:Float):Void {
		camAspect = aspect;
		camHH = camHW / camAspect;
	}

	public function translateCamera(tx:Float, ty:Float):Void {
		camX += 2 * camHW * tx;
		camY += 2 * camHH * ty;
		normalizeTranslation();
	}

	public function scaleCamera(scale:Float):Void {
		camHW *= scale;
		camHH = camHW / camAspect;
	}

	function normalizeTranslation():Void {
		final ix = Math.floor(camX);
		final iy = Math.floor(camY);
		if (ix != 0 || iy != 0) {
			camX -= ix;
			camY -= iy;
			refLevel.translate(ix, iy);
			trace(refLevel.toString());
		}
	}

	public function normalizeZoom(resolutionX:Float):Void {
		var normalized = false;
		while (resolutionX / (2 * camHW * 2048) < 2) {
			goUp();
			normalized = true;
		}
		while (resolutionX / (2 * camHW * 2048 * 2048) > 2) {
			goDown();
			normalized = true;
		}
		if (normalized)
			trace(refLevel.toString());
	}

	public function getViewInfo(resX:Float, resY:Float):{
		visibleTiles:Array<Array<Array<Int>>>,
		cameraBounds:Array<Float>,
		rawCameraBounds:Array<Float>
	} {
		final marginW = 2 * camHW / resX;
		final marginH = 2 * camHH / resY;
		final hw = camHW + marginW;
		final hh = camHH + marginH;
		final minX = Math.floor((camX - hw) * 4);
		final maxX = Math.floor((camX + hw) * 4);
		final minY = Math.floor((camY - hh) * 4);
		final maxY = Math.floor((camY + hh) * 4);
		final w = maxX - minX + 1;
		final h = maxY - minY + 1;
		assert(w <= 16 && h <= 16);
		final res = [for (y in 0...h) [for (x in 0...w) [0, 0]]];
		final time = refLevel.time;
		for (y in minY...maxY + 1) {
			for (x in minX...maxX + 1) {
				final pattern = refLevel.getPatternOfCell(x >> 2, y >> 2);
				final tile = sampler.getTile(time, pattern, x & 3, y & 3);
				final ptile = sampler.getTile(time - 1, pattern, x & 3, y & 3);
				final iy = y - minY;
				final ix = x - minX;
				res[iy][ix][0] = tile;
				res[iy][ix][1] = ptile;
			}
		}
		final offX = minX / 4;
		final offY = minY / 4;
		return {
			visibleTiles: res,
			cameraBounds: [camX - camHW - offX, camY - camHH - offY, camX + camHW - offX, camY + camHH - offY],
			rawCameraBounds: [camX - camHW, camY - camHH, camX + camHW, camY + camHH]
		};
	}

	public function step(speedCoeff:Float):Void {
		final speed = speedCoeff * Math.pow(Main.PERIOD, Math.log(max(camHW, camHH)) / Math.log(2048)) * 50;
		timeFract += speed;
		final delta = Math.floor(timeFract);
		if (delta != 0) {
			timeFract -= delta;
			if (refLevel.forward(delta))
				trace(refLevel.toString());
		}
	}

	public function getTimeFract():Int {
		return Std.int(Main.PERIOD * timeFract);
	}

	function goUp():Void {
		camX += refLevel.posX;
		camY += refLevel.posY;
		camX /= 2048;
		camY /= 2048;
		camHW /= 2048;
		camHH /= 2048;
		timeFract = refLevel.time / Main.PERIOD;
		refLevel = refLevel.getParent();
		trace("going up");
	}

	function goDown():Void {
		camX *= 2048;
		camY *= 2048;
		camX += (Math.random() * 2 - 1) * 1e-9;
		camY += (Math.random() * 2 - 1) * 1e-9;
		camHW *= 2048;
		camHH *= 2048;
		final posX = Math.floor(camX);
		final posY = Math.floor(camY);
		camX -= posX;
		camY -= posY;
		refLevel = refLevel.makeSubLevel(posX, posY, Std.int(timeFract * Main.PERIOD));
		timeFract = Main.TRANSITION_END / Main.PERIOD;
		trace("going down");
	}
}
