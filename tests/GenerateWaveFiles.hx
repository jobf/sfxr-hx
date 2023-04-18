import haxe.io.Bytes;
import Sfxr;

class GenerateWaveFiles {
	static public function main() {
		var synth = new Synth();

		var write_wave:(name:String, preset:Parameters) -> Void = (name, preset) -> {
			var wave_data:Bytes = synth.generate(preset);
			write_to_disk(name, wave_data);
		}

		var make_preset:(configure:Parameters->Void) -> Parameters = configure -> {
			var preset:Parameters = {};
			configure(preset);
			return preset;
		}

		write_wave("blip_select", make_preset(params -> Configure.blip_select(params)));
		write_wave("explosion", make_preset(params -> Configure.explosion(params)));
		write_wave("hit_hurt", make_preset(params -> Configure.hit_hurt(params)));
		write_wave("jump", make_preset(params -> Configure.jump(params)));
		write_wave("laser_shoot", make_preset(params -> Configure.laser_shoot(params)));
		write_wave("pickup_coin", make_preset(params -> Configure.pickup_coin(params)));
		write_wave("power_up", make_preset(params -> Configure.power_up(params)));
	}

	static function write_to_disk(file_name:String, data:Bytes) {
		var samplingRate = 44100;
		var bitsPerSample = 16;
		var channels = 1;

		var wave:format.wav.Data.WAVE = {
			header: {
				format: WF_PCM,
				channels: channels,
				samplingRate: samplingRate,
				byteRate: Std.int(samplingRate * channels * bitsPerSample / 8),
				blockAlign: Std.int(channels * bitsPerSample / 8),
				bitsPerSample: bitsPerSample
			},
			data: data,
			cuePoints: []
		}

		var output = sys.io.File.write('$file_name.wav', true);
		var writer = new format.wav.Writer(output);
		writer.write(wave);
	}
}
