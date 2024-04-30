import haxe.io.Bytes;
import haxe.io.BytesInput;
import js.Browser;
import js.Syntax;
import js.lib.Promise;
import format.png.Reader;
import format.png.Tools;

/**
 * ...
 */

class PNGLoader {
	public static function loadImages(sources:Array<String>, onFinished:(pixelData:Array<Array<Int>>) -> Void, onError:Void -> Void = null):Void {
		Promise.all([
			for (source in sources)
				Browser.window.fetch(source)
					.then(response -> response.arrayBuffer())
					.then(buf ->
						Tools.extract32(
							new Reader(
								new BytesInput(Bytes.ofData(buf))
							).read()
						)
					)
		])
		.then(pngs -> {
			onFinished([for (png in pngs) Syntax.code("Array.from(new Uint32Array({0}.b.buffer))", png) ]);
		})
		.catchError(error -> {
			if (onError != null) onError();
		});
	}
}
