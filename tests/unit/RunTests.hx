import Sfxr;
import utest.Runner;
import utest.ui.Report;
import utest.Test;
import utest.Assert;

class RunTests {
	public static function main() {
		var runner = new Runner();
		runner.addCase(new Tests());
		Report.create(runner);
		runner.run();
	}
}

class Tests extends Test {
	function test_preset_from_string() {
		var expected:Parameters = Configure.from_string("0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0,1.1,1.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9,2.0,2.1,2.2,2.3");

		Assert.equals(expected.wave_type, 0);
		Assert.equals(expected.attack_time, 0.1);
		Assert.equals(expected.sustain_time, 0.2);
		Assert.equals(expected.sustain_punch, 0.3);
		Assert.equals(expected.decay_time, 0.4);
		Assert.equals(expected.start_frequency, 0.5);
		Assert.equals(expected.min_frequency, 0.6);
		Assert.equals(expected.slide, 0.7);
		Assert.equals(expected.delta_slide, 0.8);
		Assert.equals(expected.vibrato_depth, 0.9);
		Assert.equals(expected.vibrato_speed, 1.0);
		Assert.equals(expected.change_amount, 1.1);
		Assert.equals(expected.change_speed, 1.2);
		Assert.equals(expected.square_duty, 1.3);
		Assert.equals(expected.duty_sweep, 1.4);
		Assert.equals(expected.repeat_speed, 1.5);
		Assert.equals(expected.phaser_offset, 1.6);
		Assert.equals(expected.phaser_sweep, 1.7);
		Assert.equals(expected.lp_filter_cutoff, 1.8);
		Assert.equals(expected.lp_filter_cutoff_sweep, 1.9);
		Assert.equals(expected.lp_filter_resonance, 2.0);
		Assert.equals(expected.hp_filter_cutoff, 2.1);
		Assert.equals(expected.hp_filter_cutoff_sweep, 2.2);
		Assert.equals(expected.master_volume, 2.3);
	}

	function test_preset_to_string() {
		var preset:Parameters = {
			wave_type: 0,
			attack_time: 0.1,
			sustain_time: 0.2,
			sustain_punch: 0.3,
			decay_time: 0.4,
			start_frequency: 0.5,
			min_frequency: 0.6,
			slide: 0.7,
			delta_slide: 0.8,
			vibrato_depth: 0.9,
			vibrato_speed: 1.0,
			change_amount: 1.1,
			change_speed: 1.2,
			square_duty: 1.3,
			duty_sweep: 1.4,
			repeat_speed: 1.5,
			phaser_offset: 1.6,
			phaser_sweep: 1.7,
			lp_filter_cutoff: 1.8,
			lp_filter_cutoff_sweep: 1.9,
			lp_filter_resonance: 2.0,
			hp_filter_cutoff: 2.1,
			hp_filter_cutoff_sweep: 2.2,
			master_volume: 2.3,
		}

		var text = Configure.to_string(preset);
		var expected = "0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1,1.1,1.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9,2,2.1,2.2,2.3";
		Assert.equals(expected, text);
	}

	function test_zeros_to_string(){
		var text = Configure.to_string({});
		var expected = "0,,0.3,,0.4,0.3,,,,,,,,,,,,,1,,,,,0.8";
		Assert.equals(expected, text);
	}

	function test_zeros_from_string(){
		var preset = Configure.from_string("0,,0.3,,0.4,0.3,,,,,,,,,,,,,1,,,,,0.8");
		var expected:Parameters = {}
		Assert.equals(expected.wave_type, preset.wave_type);
		Assert.equals(expected.attack_time, preset.attack_time);
		Assert.equals(expected.sustain_time, preset.sustain_time);
		Assert.equals(expected.sustain_punch, preset.sustain_punch);
		Assert.equals(expected.decay_time, preset.decay_time);
		Assert.equals(expected.start_frequency, preset.start_frequency);
		Assert.equals(expected.min_frequency, preset.min_frequency);
		Assert.equals(expected.slide, preset.slide);
		Assert.equals(expected.delta_slide, preset.delta_slide);
		Assert.equals(expected.vibrato_depth, preset.vibrato_depth);
		Assert.equals(expected.vibrato_speed, preset.vibrato_speed);
		Assert.equals(expected.change_amount, preset.change_amount);
		Assert.equals(expected.change_speed, preset.change_speed);
		Assert.equals(expected.square_duty, preset.square_duty);
		Assert.equals(expected.duty_sweep, preset.duty_sweep);
		Assert.equals(expected.repeat_speed, preset.repeat_speed);
		Assert.equals(expected.phaser_offset, preset.phaser_offset);
		Assert.equals(expected.phaser_sweep, preset.phaser_sweep);
		Assert.equals(expected.lp_filter_cutoff, preset.lp_filter_cutoff);
		Assert.equals(expected.lp_filter_cutoff_sweep, preset.lp_filter_cutoff_sweep);
		Assert.equals(expected.lp_filter_resonance, preset.lp_filter_resonance);
		Assert.equals(expected.hp_filter_cutoff, preset.hp_filter_cutoff);
		Assert.equals(expected.hp_filter_cutoff_sweep, preset.hp_filter_cutoff_sweep);
		Assert.equals(expected.master_volume, preset.master_volume);
	}
}
