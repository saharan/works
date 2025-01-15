import js.lib.webassembly.Global;
import js.lib.webassembly.Memory;

typedef WasmLogic = {
	function particles():Int;
	function cells():Int;
	function setGrid(gw:Int, gh:Int):Void;
	function p2g():Void;
	function updateGrid(gravityX:Float, gravityY:Float, mouseX:Float, mouseY:Float, dmouseX:Float, dmouseY:Float, radius:Float):Void;
	function g2p():Void;
	final memory:Memory;
	final numP:Global;
}
