# sfxr-hx

Pure haxe implementation of Sfxr.

## Bring your own framework

Wave data is stored in haxe.io.Bytes and can easily be integrated to your framework of choice.

## Example

All parts of the library are contained in a single import.

Example of loading a preset and generating 16 bit mono wave data.

```hx
import Sfxr;

function generate_wave_data():Void
{
	var:preset:Parameters = {};
	Configure.explosion(preset);

	var synth:Synth = new Synth();
	var wave_data:Bytes = synth.generate(preset);
}
```

## Test

Generate each of the preset variants and save to disk.

```
cd tests
haxe make_waves.hxml
```

## History

### 2007 Tomas Pettersson - sfxr

Original C++ implementation

https://github.com/grimfang4/sfxr


### 2009 Mike Wiering - haXe SFXR

HaXe/Flash implementation

https://github.com/grimfang4/sfxr

### 2010 Thomas Vian - as3fxr

Flash as3 implementation

https://github.com/SFBTom/as3sfxr

### 2014 Fernando Serboncini - Haxe sfxr

Haxe/OpenFL implementation

https://github.com/fserb/sfxr
