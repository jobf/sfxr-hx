/*
   Copyright (c) 2007 Tomas Pettersson <drpetter@gmail.com>
   Copyright (c) 2023 James O B Fisher
	
   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
   THE SOFTWARE.
*/

import haxe.io.Bytes;

class Synth {
	var params:Parameters;

	public function new() {}

	public function generate(preset:Parameters):Bytes {
		params = preset;
		reset(true);
		var wave_data = new WaveData();
		synthesize(wave_data);
		return wave_data.bytes;
	}

	var master_volume:Float; // master_volume * master_volume (for quick calculations)

	var wave_type:Int; // The type of wave to generate

	var envelope_volume:Float; // Current volume of the envelope
	var envelope_stage:Int; // Current stage of the envelope (attack, sustain, decay, end)
	var envelope_time:Float; // Current time through current enelope stage
	var envelope_length:Float; // Length of the current envelope stage
	var envelope_length_0:Float; // Length of the attack stage
	var envelope_length_1:Float; // Length of the sustain stage
	var envelope_length_2:Float; // Length of the decay stage
	var envelope_full_length:Float; // Full length of the volume envelop (and therefore sound)

	var sustain_punch:Float; // The punch factor (louder at begining of sustain)

	var phase:Int; // Phase through the wave
	var pos:Float; // Phase expresed as a Float from 0-1, used for fast sin approx
	var period:Float; // Period of the wave
	var max_period:Float; // Maximum period before sound stops (from min_frequency)

	var slide:Float; // Note slide
	var delta_slide:Float; // Change in slide
	var min_frequency:Float; // Minimum frequency before stopping

	var vibrato_phase:Float; // Phase through the vibrato sine wave
	var vibrato_speed:Float; // Speed at which the vibrato phase moves
	var vibrato_amplitude:Float; // Amount to change the period of the wave by at the peak of the vibrato wave

	var change_amount:Float; // Amount to change the note by
	var change_time:Int; // Counter for the note change
	var change_limit:Int; // Once the time reaches this limit, the note changes

	var square_duty:Float; // Offset of center switching point in the square wave
	var duty_sweep:Float; // Amount to change the duty by

	var repeat_time:Int; // Counter for the repeats
	var repeat_limit:Int; // Once the time reaches this limit, some of the variables are reset

	var phaser_enabled:Bool; // If the phaser is active
	var phaser_offset:Float; // Phase offset for phaser effect
	var phaser_delta_offset:Float; // Change in phase offset
	var phaser_offset_int:Int; // Integer phaser offset, for bit maths
	var phaser_pos:Int; // Position through the phaser buffer
	var phaser_buffer:Array<Float>; // Buffer of wave values used to create the out of phase second wave

	var filters:Bool; // If the filters are active
	var lp_filter_pos:Float; // Adjusted wave position after low-pass filter
	var lp_filter_pos_previous:Float; // Previous low-pass wave position
	var lp_filter_delta_pos:Float; // Change in low-pass wave position, as allowed by the cutoff and damping
	var lp_filter_cutoff:Float; // Cutoff multiplier which adjusts the amount the wave position can move
	var lp_filter_cutoff_delta:Float; // Speed of the low-pass cutoff multiplier
	var lp_filter_damping:Float; // Damping muliplier which restricts how fast the wave position can move
	var lp_filter_enabled:Bool; // If the low pass filter is active

	var hp_filter_pos:Float; // Adjusted wave position after high-pass filter
	var hp_filter_cutoff:Float; // Cutoff multiplier which adjusts the amount the wave position can move
	var hp_filter_cutoff_delta:Float; // Speed of the high-pass cutoff multiplier

	var noise_buffer:Array<Float>; // Buffer of random values used to generate noise

	var super_sample:Float; // Actual sample writen to the wave
	var sample_count:Int; // Number of samples added to the buffer sample
	var buffer_sample:Float; // Another super_sample used to create a 22050Hz wave

	var samples:Array<Float>;

	/**
	 * Resets the running variables from the params
	 * Used once at the start (total reset) and for the repeat effect (partial reset)
	 * @param total_reset If the reset is total
	 */
	function reset(total_reset:Bool) {
		// Shorter reference
		var p:Parameters = params;

		// diff 0.001 -> 0.000001
 		period = 100.0 / (p.start_frequency * p.start_frequency + 0.001);
 		max_period = 100.0 / (p.min_frequency * p.min_frequency + 0.001);

 		slide = 1.0 - p.slide * p.slide * p.slide * 0.01;
 		delta_slide = -p.delta_slide * p.delta_slide * p.delta_slide * 0.000001;

		if (p.wave_type == 0) {
	 		square_duty = 0.5 - p.square_duty * 0.5;
	 		duty_sweep = -p.duty_sweep * 0.00005;
		}

		if (p.change_amount > 0.0) {
	 		change_amount = 1.0 - p.change_amount * p.change_amount * 0.9;
		} else {
	 		change_amount = 1.0 + p.change_amount * p.change_amount * 10.0;
		}

 		change_time = 0;

		if (p.change_speed == 1.0) {
	 		change_limit = 0;
		} else {
	 		change_limit = Std.int((1.0 - p.change_speed) * (1.0 - p.change_speed) * 20000 + 32);
		}

		if (total_reset) {
			master_volume = p.master_volume * p.master_volume;

			wave_type = p.wave_type;

			if (p.sustain_time < 0.01) {
				p.sustain_time = 0.01;
			}

			var totalTime = p.attack_time + p.sustain_time + p.decay_time;
			if (totalTime < 0.18) {
				var multiplier = 0.18 / totalTime;
				p.attack_time *= multiplier;
				p.sustain_time *= multiplier;
				p.decay_time *= multiplier;
			}

			sustain_punch = p.sustain_punch;

	 		phase = 0;

	 		min_frequency = p.min_frequency;

	 		filters = p.lp_filter_cutoff != 1.0 || p.hp_filter_cutoff != 0.0;

	 		lp_filter_pos = 0.0;
	 		lp_filter_delta_pos = 0.0;
	 		lp_filter_cutoff = p.lp_filter_cutoff * p.lp_filter_cutoff * p.lp_filter_cutoff * 0.1;
	 		lp_filter_cutoff_delta = 1.0 + p.lp_filter_cutoff_sweep * 0.0001;
	 		lp_filter_damping = 5.0 / (1.0 + p.lp_filter_resonance * p.lp_filter_resonance * 20.0) * (0.01 + lp_filter_cutoff);
			if (lp_filter_damping > 0.8)
		 		lp_filter_damping = 0.8;
	 		lp_filter_damping = 1.0 - lp_filter_damping;
	 		lp_filter_enabled = p.lp_filter_cutoff != 1.0;

	 		hp_filter_pos = 0.0;
	 		hp_filter_cutoff = p.hp_filter_cutoff * p.hp_filter_cutoff * 0.1;
	 		hp_filter_cutoff_delta = 1.0 + p.hp_filter_cutoff_sweep * 0.0003;

	 		vibrato_phase = 0.0;
	 		vibrato_speed = p.vibrato_speed * p.vibrato_speed * 0.01;
	 		vibrato_amplitude = p.vibrato_depth * 0.5;

			envelope_volume = 0.0;
			envelope_stage = 0;
			envelope_time = 0;
			envelope_length_0 = p.attack_time * p.attack_time * 100000.0;
			envelope_length_1 = p.sustain_time * p.sustain_time * 100000.0;
			envelope_length_2 = p.decay_time * p.decay_time * 100000.0 + 10;
			envelope_length = envelope_length_0;
			envelope_full_length = envelope_length_0 + envelope_length_1 + envelope_length_2;

	 		phaser_enabled = p.phaser_offset != 0.0 || p.phaser_sweep != 0.0;

	 		phaser_offset = p.phaser_offset * p.phaser_offset * 1020.0;
			if (p.phaser_offset < 0.0) {
		 		phaser_offset = -phaser_offset;
			}
	 		phaser_delta_offset = p.phaser_sweep * p.phaser_sweep * p.phaser_sweep * 0.2;
	 		phaser_pos = 0;

	 		phaser_buffer = new Array<Float>();
			for (i in 0...1024)
		 		phaser_buffer.push(0.0);
	 		noise_buffer = new Array<Float>();
			for (i in 0...32)
		 		noise_buffer.push(Math.random() * 2.0 - 1.0);

	 		repeat_time = 0;

			if (p.repeat_speed == 0.0) {
		 		repeat_limit = 0;
			} else {
		 		repeat_limit = Std.int((1.0 - p.repeat_speed) * (1.0 - p.repeat_speed) * 20000) + 32;
			}
		}
	}

	/**
	 * Writes the wave to the supplied buffer ByteArray
	 * @param buffer    A ByteArray to write the wave to
	 * @param waveData  If the wave should be written for the waveData
	 */
	function synthesize(data:WaveData) {
		var finished = false;

 		sample_count = 0;
 		buffer_sample = 0.0;
		samples = [];

		while (!finished) {
			// Repeats every repeat_limit times, partially resetting the sound parameters
			if (repeat_limit != 0) {
				if (++repeat_time >= repeat_limit) {
			 		repeat_time = 0;
					reset(false);
				}
			}

			// If change_limit is reached, shifts the pitch
			if (change_limit != 0) {
				if (++change_time >= change_limit) {
			 		change_limit = 0;
			 		period *= change_amount;
				}
			}

			// Acccelerate and apply slide
	 		slide += delta_slide;
	 		period *= slide;

			// Checks for frequency getting too low, and stops the sound if a min_frequency was set
			if (period > max_period) {
		 		period = max_period;
				if (min_frequency > 0.0) {
					finished = true;
				}
			}

			var period_temp:Float = period;

			// Applies the vibrato effect
			if (vibrato_amplitude > 0.0) {
		 		vibrato_phase += vibrato_speed;
				period_temp = period * (1.0 + Math.sin(vibrato_phase) * vibrato_amplitude);
			}

			period_temp = Std.int(period_temp);
			if (period_temp < 8)
				period_temp = 8;

			// Sweeps the square duty
			if (wave_type == 0) {
		 		square_duty += duty_sweep;
				if (square_duty < 0.0)
			 		square_duty = 0.0;
				else if (square_duty > 0.5)
			 		square_duty = 0.5;
			}

			// Moves through the different stages of the volume envelope
			if (++envelope_time > envelope_length) {
				envelope_time = 0;
				switch (++envelope_stage) {
					case 1:
						envelope_length = envelope_length_1;
					case 2:
						envelope_length = envelope_length_2;
				}
			}

			// Sets the volume based on the position in the envelope
			switch (envelope_stage) {
				case 0:
					envelope_volume = envelope_time / envelope_length_0;
				case 1:
					envelope_volume = 1.0 + (1.0 - envelope_time / envelope_length_1) * 2.0 * sustain_punch;
				case 2:
					envelope_volume = 1.0 - envelope_time / envelope_length_2;
				case 3:
					envelope_volume = 0.0;
					finished = true;
			}

			// Moves the phaser offset
			if (phaser_enabled) {
		 		phaser_offset += phaser_delta_offset;
		 		phaser_offset_int = Std.int(phaser_offset);
				if (phaser_offset_int < 0)
			 		phaser_offset_int = -phaser_offset_int;
				else if (phaser_offset_int > 1023)
			 		phaser_offset_int = 1023;
			}

			// Moves the high-pass filter cutoff
			if (filters && hp_filter_cutoff_delta != 0.0) {
		 		hp_filter_cutoff *= hp_filter_cutoff_delta;
				if (hp_filter_cutoff < 0.00001)
			 		hp_filter_cutoff = 0.00001;
				else if (hp_filter_cutoff > 0.1)
			 		hp_filter_cutoff = 0.1;
			}

	 		super_sample = 0.0;
			for (j in 0...8) {
				var sample:Float = 0.0;
				// Cycles through the period
		 		phase++;
				if (phase >= period_temp) {
			 		phase = phase - Std.int(period_temp);
					// Generates new random noise for this period
					if (wave_type == 3) {
						for (n in 0...32)
					 		noise_buffer[n] = Math.random() * 2.0 - 1.0;
					}
				}
				// Gets the sample from the oscillator
				switch (wave_type) {
					case 0: // Square wave
						sample = ((phase / period_temp) < square_duty) ? 0.5 : -0.5;
					case 1: // Saw wave
						sample = 1.0 - (phase / period_temp) * 2.0;
					case 2: // Sine wave (fast and accurate approx)
				 		pos = phase / period_temp;
				 		pos = pos > 0.5 ? (pos - 1.0) * 6.28318531 : pos * 6.28318531;
						sample = pos < 0 ? 1.27323954 * pos + .405284735 * pos * pos : 1.27323954 * pos - 0.405284735 * pos * pos;
						sample = sample < 0 ? .225 * (sample * -sample - sample) + sample : .225 * (sample * sample - sample) + sample;
					case 3: // Noise
						sample = noise_buffer[Std.int(phase * 32 / Std.int(period_temp))];
				}

				// Applies the low and high pass filters
				if (filters) {
			 		lp_filter_pos_previous = lp_filter_pos;
			 		lp_filter_cutoff *= lp_filter_cutoff_delta;
					if (lp_filter_cutoff < 0.0)
				 		lp_filter_cutoff = 0.0;
					else if (lp_filter_cutoff > 0.1)
				 		lp_filter_cutoff = 0.1;

					if (lp_filter_enabled) {
				 		lp_filter_delta_pos += (sample - lp_filter_pos) * lp_filter_cutoff;
				 		lp_filter_delta_pos *= lp_filter_damping;
					} else {
				 		lp_filter_pos = sample;
				 		lp_filter_delta_pos = 0.0;
					}

			 		lp_filter_pos += lp_filter_delta_pos;

			 		hp_filter_pos += lp_filter_pos - lp_filter_pos_previous;
			 		hp_filter_pos *= 1.0 - hp_filter_cutoff;

					sample = hp_filter_pos;
				}

				// Applies the phaser effect
				if (phaser_enabled) {
			 		phaser_buffer[phaser_pos & 1023] = sample;
					sample += phaser_buffer[(phaser_pos - phaser_offset_int + 1024) & 1023];
			 		phaser_pos = (phaser_pos + 1) & 1023;
				}

		 		super_sample += sample;
			}
			// Averages out the super samples and applies volumes
	 		super_sample = master_volume * envelope_volume * super_sample / 8.0;

			// Clipping if too loud
			if (super_sample > 1.0)
		 		super_sample = 1.0;
			else if (super_sample < -1.0)
		 		super_sample = -1.0;

			samples.push(super_sample);

			var val:Int = Std.int(32767.0 * super_sample);
			data.write_short(val);
		}
	}
}

@:structInit
class Parameters {
	public var wave_type:Int = 0; // Shape of the wave (0:square, 1:saw, 2:sin or 3:noise)
	public var master_volume:Float = 0.8; // Overall volume of the sound (0 to 1)

	public var attack_time:Float = 0.0; // Length of the volume envelope attack (0 to 1)
	public var sustain_time:Float = 0.3; // Length of the volume envelope sustain (0 to 1)
	public var sustain_punch:Float = 0.0; // Tilts the sustain envelope for more 'pop' (0 to 1)
	public var decay_time:Float = 0.4; // Length of the volume envelope decay (yes, I know it's called release) (0 to 1)

	public var start_frequency:Float = 0.3; // Base note of the sound (0 to 1)
	public var min_frequency:Float = 0.0; // If sliding, the sound will stop at this frequency, to prevent really low notes (0 to 1)

	public var slide:Float = 0.0; // Slides the note up or down (-1 to 1)
	public var delta_slide:Float = 0.0; // Accelerates the slide (-1 to 1)

	public var vibrato_depth:Float = 0.0; // Strength of the vibrato effect (0 to 1)
	public var vibrato_speed:Float = 0.0; // Speed of the vibrato effect (i.e. frequency) (0 to 1)

	public var change_amount:Float = 0.0; // Shift in note, either up or down (-1 to 1)
	public var change_speed:Float = 0.0; // How fast the note shift happens (only happens once) (0 to 1)

	public var square_duty:Float = 0.0; // Controls the ratio between the up and down states of the square wave, changing the tibre (0 to 1)
	public var duty_sweep:Float = 0.0; // Sweeps the duty up or down (-1 to 1)

	public var repeat_speed:Float = 0.0; // Speed of the note repeating - certain variables are reset each time (0 to 1)

	public var phaser_offset:Float = 0.0; // Offsets a second copy of the wave by a small phase, changing the tibre (-1 to 1)
	public var phaser_sweep:Float = 0.0; // Sweeps the phase up or down (-1 to 1)

	public var lp_filter_cutoff:Float = 1.0; // Frequency at which the low-pass filter starts attenuating higher frequencies (0 to 1)
	public var lp_filter_cutoff_sweep:Float = 0.0; // Sweeps the low-pass cutoff up or down (-1 to 1)
	public var lp_filter_resonance:Float = 0.0; // Changes the attenuation rate for the low-pass filter, changing the timbre (0 to 1)

	public var hp_filter_cutoff:Float = 0.0; // Frequency at which the high-pass filter starts attenuating lower frequencies (0 to 1)
	public var hp_filter_cutoff_sweep:Float = 0.0; // Sweeps the high-pass cutoff up or down (-1 to 1)
}

class Configure {
	static var _seed:Null<Int>;

	public static function pickup_coin(params:Parameters) {
		params.start_frequency = 0.4 + random() * 0.5;
		params.sustain_time = random() * 0.1;
		params.decay_time = 0.1 + random() * 0.4;
		params.sustain_punch = 0.3 + random() * 0.3;
		if (random() < 0.5) {
			params.change_speed = 0.5 + random() * 0.2;
			params.change_amount = 0.2 + random() * 0.4;
		}
	}

	public static function laser_shoot(params:Parameters) {
		params.wave_type = Std.int(random() * 3);
		if (params.wave_type == 2 && random() < 0.5)
			params.wave_type = Std.int(random() * 2);
		params.start_frequency = 0.5 + random() * 0.5;
		params.min_frequency = params.start_frequency - 0.2 - random() * 0.6;
		if (params.min_frequency < 0.2)
			params.min_frequency = 0.2;
		params.slide = -0.15 - random() * 0.2;
		if (random() < 0.33) {
			params.start_frequency = 0.3 + random() * 0.6;
			params.min_frequency = random() * 0.1;
			params.slide = -0.35 - random() * 0.3;
		}
		if (random() < 0.5) {
			params.square_duty = random() * 0.5;
			params.duty_sweep = random() * 0.2;
		} else {
			params.square_duty = 0.4 + random() * 0.5;
			params.duty_sweep = -random() * 0.7;
		}
		params.sustain_time = 0.1 + random() * 0.2;
		params.decay_time = random() * 0.4;
		if (random() < 0.5)
			params.sustain_punch = random() * 0.3;
		if (random() < 0.33) {
			params.phaser_offset = random() * 0.2;
			params.phaser_sweep = -random() * 0.2;
		}
		if (random() < 0.5)
			params.hp_filter_cutoff = random() * 0.3;
	}

	public static function explosion(params:Parameters) {
		params.wave_type = 3;
		if (random() < 0.5) {
			params.start_frequency = 0.1 + random() * 0.4;
			params.slide = -0.1 + random() * 0.4;
		} else {
			params.start_frequency = 0.2 + random() * 0.7;
			params.slide = -0.2 - random() * 0.2;
		}

		params.start_frequency *= params.start_frequency;

		if (random() < 0.2)
			params.slide = 0.0;
		if (random() < 0.33)
			params.repeat_speed = 0.3 + random() * 0.5;

		params.sustain_time = 0.1 + random() * 0.3;
		params.decay_time = random() * 0.5;
		params.sustain_punch = 0.2 + random() * 0.6;

		if (random() < 0.5) {
			params.phaser_offset = -0.3 + random() * 0.9;
			params.phaser_sweep = -random() * 0.3;
		}

		if (random() < 0.33) {
			params.change_speed = 0.6 + random() * 0.3;
			params.change_amount = 0.8 - random() * 1.6;
		}
	}

	public static function power_up(params:Parameters) {
		if (random() < 0.5)
			params.wave_type = 1;
		else
			params.square_duty = random() * 0.6;
		if (random() < 0.5) {
			params.start_frequency = 0.2 + random() * 0.3;
			params.slide = 0.1 + random() * 0.4;
			params.repeat_speed = 0.4 + random() * 0.4;
		} else {
			params.start_frequency = 0.2 + random() * 0.3;
			params.slide = 0.05 + random() * 0.2;
			if (random() < 0.5) {
				params.vibrato_depth = random() * 0.7;
				params.vibrato_speed = random() * 0.6;
			}
		}
		params.sustain_time = random() * 0.4;
		params.decay_time = 0.1 + random() * 0.4;
	}

	public static function hit_hurt(params:Parameters) {
		params.wave_type = Std.int(random() * 3);
		if (params.wave_type == 2)
			params.wave_type = 3;
		else if (params.wave_type == 0)
			params.square_duty = random() * 0.6;
		params.start_frequency = 0.2 + random() * 0.6;
		params.slide = -0.3 - random() * 0.4;
		params.sustain_time = random() * 0.1;
		params.decay_time = 0.1 + random() * 0.2;
		if (random() < 0.5)
			params.hp_filter_cutoff = random() * 0.3;
	}

	public static function jump(params:Parameters) {
		params.wave_type = 0;
		params.square_duty = random() * 0.6;
		params.start_frequency = 0.3 + random() * 0.3;
		params.slide = 0.1 + random() * 0.2;
		params.sustain_time = 0.1 + random() * 0.3;
		params.decay_time = 0.1 + random() * 0.2;
		if (random() < 0.5)
			params.hp_filter_cutoff = random() * 0.3;
		if (random() < 0.5)
			params.lp_filter_cutoff = 1.0 - random() * 0.6;
	}

	public static function blip_select(params:Parameters) {
		params.wave_type = Std.int(random() * 2);
		if (params.wave_type == 0)
			params.square_duty = random() * 0.6;
		params.start_frequency = 0.2 + random() * 0.4;
		params.sustain_time = 0.1 + random() * 0.1;
		params.decay_time = random() * 0.2;
		params.hp_filter_cutoff = 0.1;
	}

	static final MAX_INT:Int = 2147483647;

	static function seed(seed:Null<Int>) {
		return _seed == null ? Math.floor(Math.random() * MAX_INT) : _seed;
	}

	static function randint():Int {
		return Std.int((1103515245.0 * seed(_seed) + 12345) % MAX_INT);
	}

	static function random():Float {
		return randint() / MAX_INT;
	}

	public static function mutate(params:Parameters, mutation:Float = 0.05) {
		if (random() < 0.5)
			params.start_frequency += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.min_frequency += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.slide += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.delta_slide += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.square_duty += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.duty_sweep += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.vibrato_depth += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.vibrato_speed += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.attack_time += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.sustain_time += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.decay_time += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.sustain_punch += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.lp_filter_cutoff += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.lp_filter_cutoff_sweep += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.lp_filter_resonance += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.hp_filter_cutoff += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.hp_filter_cutoff_sweep += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.phaser_offset += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.phaser_sweep += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.repeat_speed += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.change_speed += random() * mutation * 2 - mutation;
		if (random() < 0.5)
			params.change_amount += random() * mutation * 2 - mutation;
	}

	public static function randomize(params:Parameters) {
		params.wave_type = Std.int(random() * 4);
		params.attack_time = Math.pow(random() * 2 - 1, 4);
		params.sustain_time = Math.pow(random() * 2 - 1, 2);
		params.sustain_punch = Math.pow(random() * 0.8, 2);
		params.decay_time = random();
		params.start_frequency = (random() < 0.5) ? Math.pow(random() * 2 - 1, 2) : (Math.pow(random() * 0.5, 3) + 0.5);
		params.min_frequency = 0.0;
		params.slide = Math.pow(random() * 2 - 1, 5);
		params.delta_slide = Math.pow(random() * 2 - 1, 3);
		params.vibrato_depth = Math.pow(random() * 2 - 1, 3);
		params.vibrato_speed = random() * 2 - 1;
		params.change_amount = random() * 2 - 1;
		params.change_speed = random() * 2 - 1;
		params.square_duty = random() * 2 - 1;
		params.duty_sweep = Math.pow(random() * 2 - 1, 3);
		params.repeat_speed = random() * 2 - 1;
		params.phaser_offset = Math.pow(random() * 2 - 1, 3);
		params.phaser_sweep = Math.pow(random() * 2 - 1, 3);
		params.lp_filter_cutoff = 1 - Math.pow(random(), 3);
		params.lp_filter_cutoff_sweep = Math.pow(random() * 2 - 1, 3);
		params.lp_filter_resonance = random() * 2 - 1;
		params.hp_filter_cutoff = Math.pow(random(), 5);
		params.hp_filter_cutoff_sweep = Math.pow(random() * 2 - 1, 5);

		if (params.attack_time + params.sustain_time + params.decay_time < 0.2) {
			params.sustain_time = 0.2 + random() * 0.3;
			params.decay_time = 0.2 + random() * 0.3;
		}

		if ((params.start_frequency > 0.7 && params.slide > 0.2) || (params.start_frequency < 0.2 && params.slide < -0.05)) {
			params.slide = -params.slide;
		}

		if (params.lp_filter_cutoff < 0.1 && params.lp_filter_cutoff_sweep < -0.05) {
			params.lp_filter_cutoff_sweep = -params.lp_filter_cutoff_sweep;
		}
	}

	public static function from_string(s:String):Parameters {
		var values = s.split(",");

		if (values.length != 24)
			return {};

		var float = function(x:String):Float {
			var f = Std.parseFloat(x);
			return Math.isNaN(f) ? 0 : f;
		};

		var v = Std.parseInt(values[0]);

		return {
			wave_type: v == null ? 0 : v,
			attack_time: float(values[1]),
			sustain_time: float(values[2]),
			sustain_punch: float(values[3]),
			decay_time: float(values[4]),
			start_frequency: float(values[5]),
			min_frequency: float(values[6]),
			slide: float(values[7]),
			delta_slide: float(values[8]),
			vibrato_depth: float(values[9]),
			vibrato_speed: float(values[10]),
			change_amount: float(values[11]),
			change_speed: float(values[12]),
			square_duty: float(values[13]),
			duty_sweep: float(values[14]),
			repeat_speed: float(values[15]),
			phaser_offset: float(values[16]),
			phaser_sweep: float(values[17]),
			lp_filter_cutoff: float(values[18]),
			lp_filter_cutoff_sweep: float(values[19]),
			lp_filter_resonance: float(values[20]),
			hp_filter_cutoff: float(values[21]),
			hp_filter_cutoff_sweep: float(values[22]),
			master_volume: float(values[23]),
		}
	}
}

class WaveData {
	public var bytes(default, null):Bytes;

	var write_head:Int;

	public function new(length_seconds:Int = 2, sample_rate:Int = 44100) {
		bytes = Bytes.alloc(length_seconds * sample_rate);
		write_head = 0;
	}

	public function write_short(value:Int):Void {
		bytes.set(write_head++, value);
		bytes.set(write_head++, value >> 8);
		if (write_head > bytes.length) {
			write_head = 0;
		}
	}
}