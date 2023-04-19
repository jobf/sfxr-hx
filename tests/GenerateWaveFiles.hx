import haxe.io.Bytes;

import Sfxr;

class GenerateWaveFiles {
	static public function main() {
		var synth = new Synth();

		var write_wave:(name:String, preset:Parameters) -> Void = (name, preset) -> {
			var wave_data:Bytes = synth.generate(preset);
			write_to_disk(name, wave_data);
		}

		write_wave("blip_select", Configure.blip_select());
		write_wave("explosion", Configure.explosion());
		write_wave("hit_hurt", Configure.hit_hurt());
		write_wave("jump", Configure.jump());
		write_wave("laser_shoot", Configure.laser_shoot());
		write_wave("pickup_coin", Configure.pickup_coin());
		write_wave("power_up", Configure.power_up());
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
