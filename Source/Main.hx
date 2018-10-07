package;

import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.events.TimerEvent;
import openfl.ui.Keyboard;
import openfl.ui.Mouse;
import openfl.Assets;

import openfl.display.Sprite;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.DisplayObject;
import openfl.display.FPS;
import openfl.display.Shader;
import openfl.display.Loader;
import openfl.display.LoaderInfo;

import openfl.media.Sound;

import openfl.text.Font;
import openfl.text.TextField;
import openfl.text.TextFormat;

import openfl.net.URLRequest;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;

import openfl.utils.Timer;

import motion.Actuate;
import motion.easing.Cubic;

import ui.components.ColorRect;

import sensors.SensorVL53L1X;
import sensors.vl53l1x.events.DistanceEvent;
import sensors.vl53l1x.events.SensorEvent;

import FadeShader;
import Settings;
import StyleManager;

class Main extends Sprite {

 	public static inline function min<T:Float>(t:T, t2:T):T { return t < t2 ? t : t2; }
	public static inline function max<T:Float>(t:T, t2:T):T { return t > t2 ? t : t2; }

 	//ui 
	var fps:FPS;
	var bitmap:Bitmap;
	var bar:ColorRect;
	var format:TextFormat;
	var feedbackField:TextField;
	var SoundFeedback:Sound;
	var mw:Float = 1280.0;
	
	// Sensor
	var s1:SensorVL53L1X;
	var sensorEnabled:Bool = false;
	var lastDistance = 0;

	// shader
	var fshader:FadeShader;
	var blackScreen:BitmapData;
	var front:BitmapData;
	var back:BitmapData;
	var screenRect:Rectangle;
  	var settings:Settings;
	var loader:Loader;
	var fileIndex = 0;
	var files:Array<String>=[];
	var tweenValue:Float = 0.0;
	var tweenDelay:Timer;
	var transitioning = false;
	

	public function new () {
		
		super ();

		StyleManager.initialize();
		SoundFeedback = Assets.getSound ("plonk");

		feedbackField = new TextField ();
        feedbackField.width = stage.stageWidth - 80;
        feedbackField.height = 64;
        feedbackField.y = stage.stageHeight - feedbackField.height;
       	feedbackField.defaultTextFormat = StyleManager.defaultFormat;
		feedbackField.embedFonts = true;
        feedbackField.selectable = false;
        feedbackField.multiline = true;

		mw = stage.stageWidth;

		stage.addEventListener ( KeyboardEvent.KEY_DOWN, stage_onKeyDown);

		fshader = new FadeShader ();

		//initialize Loaders for back and front
		loader = new Loader();
		loader.contentLoaderInfo.addEventListener(Event.COMPLETE, loadCompleteHandler);
		loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
		
		//initialize Reusable BitmapDataBuffers
		initBuffers();

		//
		bitmap = new Bitmap ( blackScreen );
		bitmap.shader = fshader;
		addChild(bitmap);

		bar = new ColorRect( mw , 32, 0x00CC00, 1);
		bar.y = stage.stageHeight - 32;
		addChild(bar);

		addChild(feedbackField);

		fps = new FPS(4,4,0x000000);
		addChild(fps);


		settings = Settings.init();
		if(settings.loadSuccess){
			
			fps.visible = settings.showFPS;

			listImages(settings.path);
			if(files.length>0){
				loadImage(files[0]);
			}
			
			stage.addEventListener(KeyboardEvent.KEY_DOWN, stage_onKeyDown);

		}else{
			trace('${settings.path} does not exists');
			feedbackField.text = '"${settings.path}" does not exists';
		}

		tweenDelay = new Timer(settings.displayTime ,1 );
		tweenDelay.addEventListener(TimerEvent.TIMER, nextImage );

		s1 = new SensorVL53L1X();
		if( s1.initialize() ){
			feedbackField.text = "SensorVL53L1X extension initialized!";
			s1.addEventListener ( DistanceEvent.DISTANCE,  s1_distance);
			s1.startMeasuring();
			sensorEnabled = true;
		}
	}
	
	function s1_distance (event:DistanceEvent):Void{
		feedbackField.text = 'distance ${event.distance}';
		var apct:Float = ( Math.min(mw,Math.max(0,(mw*2) - event.distance)))/ mw;
		bar.scaleX = apct;
		lastDistance = event.distance;
		if(fshader!=null){
			fshader.fade.value = [1-apct];
			bitmap.invalidate();
		};
	}

	function initBuffers(dispose:Bool=false){

		//initialize Reusable BitmapDataBuffers
		if(dispose && blackScreen!=null){
			blackScreen.dispose();
			front.dispose();
			back.dispose();
		}
		blackScreen = new BitmapData( stage.stageWidth,stage.stageHeight,true,0x000000);
		front		= new BitmapData( stage.stageWidth,stage.stageHeight,true,0x000000);
		back		= new BitmapData( stage.stageWidth,stage.stageHeight,true,0x000000);
		screenRect  = new Rectangle(0,0, stage.stageWidth,stage.stageHeight);
	}


	function listImages(directory:String = "./images/") {
		files = [];

		if (sys.FileSystem.exists(directory)) {
			for (file in sys.FileSystem.readDirectory(directory)) {
				var path = haxe.io.Path.join([directory, file]);
				// ** IGNORE SUBDIRECTORIES **
				if (!sys.FileSystem.isDirectory(path)) {
					if( ["jpg","JPG","png","PNG"].indexOf(haxe.io.Path.extension(file)) > -1 && ( file.indexOf("._") != 0) ){
						files.push(path);
					}
				}
			}

			// sort files by name
			files.sort(function(a,b) return Reflect.compare(a.toLowerCase(), b.toLowerCase()) );

		} else {
			trace('$directory does not exists');
			feedbackField.text = '"$directory" does not exists. Press ESC to Quit';
		}
	}

	function nextImage(e:Event = null){

		if( fileIndex < files.length-1 ) {
			fileIndex++;
		}else {
			fileIndex = 0;
		}
		transitioning = true;
		loadImage( files[ fileIndex ] );
	}

	function fitBitmapData( source:BitmapData, destination:BitmapData){
		var w = destination.width; var h = destination.height;
		var wratio:Float;
		var hratio:Float;
		
		switch(settings.contentFill){
			case ContentFill.FIT:
				wratio = hratio = Math.min( w / source.width,  h / source.height);
			case ContentFill.FILL:
				wratio = hratio = Math.max( w / source.width,  h / source.height);
			case ContentFill.SCALE:
				wratio = w / source.width;
				hratio = h / source.height;
			default:
				wratio = hratio = Math.min( w / source.width,  h / source.height);
				trace('Invalid contentFill mode ${settings.contentFill}. Defaulting to fit (lowercase!)');
		}

		var matrix:Matrix = new Matrix();
		matrix.scale(wratio, hratio);
		matrix.translate(  (w- (wratio*source.width))*.5 , (h- (hratio*source.height))*.5);

		destination.fillRect(screenRect, 0xFF000000);
		destination.draw(source,matrix,null,null,true);
	}

	function startTransition(back:BitmapData, front:BitmapData){
		tweenValue = 0.0;
		fshader.img1.input = back;
		fshader.img2.input = front;
		fshader.fade.value = [tweenValue];
		//bitmap.shader = fshader;
		startTween();
	}	

	private function startTween(e:Event=null){
		Actuate.tween(this, (settings.transitionTime / 1000), {tweenValue:1}).ease(Cubic.easeIn).onComplete(tweenComplete).onUpdate(tweenUpdate );
	}

	private function tweenComplete(){
		//tweenDelay.start();
		if(settings.showFileName) feedbackField.text = files[fileIndex];
		transitioning = false;
	}

	private function tweenUpdate(){
		fshader.fade.value = [tweenValue];
		bitmap.invalidate();
	}

	private function loadImage(frontImage:String):Void
	{
		loader.load(new URLRequest(frontImage));
	}

	private function loadCompleteHandler(event:Event):Void 
	{
		back.fillRect(screenRect, 0xFF000000);
		back.draw(front);
		fitBitmapData( cast(loader.content,Bitmap).bitmapData, front);
		transitioning = true;
		startTransition(back,front);
		cast(loader.content,Bitmap).bitmapData.dispose();
		loader.unload();
	}
		
	private function ioErrorHandler(event:IOErrorEvent):Void 
	{
		trace('Image load failed ${event.toString()}');
	}
	

	private function stage_onKeyDown (event:KeyboardEvent):Void
	{	
		switch (event.keyCode) {
			case Keyboard.SPACE:
				if(!transitioning){
		 			nextImage();
				}
			case Keyboard.S:
				if(sensorEnabled){
					s1.stopMeasuring();
				}
				else{
					s1.startMeasuring();
				}
				sensorEnabled = !sensorEnabled;

			case Keyboard.ESCAPE|Keyboard.F4:
				openfl.system.System.exit(0);
		}
	}
}