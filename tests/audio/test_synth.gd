extends GdUnitTestSuite
## T4.6: procedural sound generation — PCM buffers have the right length and rate, are not
## silent, never clip, loop seamlessly when meant to loop, and every sound of the bank exists.


func _peak(samples: PackedFloat32Array) -> float:
	var peak := 0.0
	for s in samples:
		peak = maxf(peak, absf(s))
	return peak


func test_tone_has_the_requested_length_and_is_audible() -> void:
	var samples := Synth.tone(440.0, 0.25)
	assert_int(samples.size()).is_equal(roundi(0.25 * Synth.MIX_RATE))
	assert_float(_peak(samples)).is_greater(0.3)
	assert_float(_peak(samples)).is_less_equal(1.0)


func test_tone_fades_in_and_out_without_clicks() -> void:
	var samples := Synth.tone(440.0, 0.2)
	assert_float(absf(samples[0])).is_less(0.01)
	assert_float(absf(samples[samples.size() - 1])).is_less(0.02)


func test_glide_changes_pitch_over_the_tone() -> void:
	# Count zero crossings in the first and last quarter: a rising glide crosses more often later.
	var samples := Synth.tone(300.0, 0.4, 0.005, 1.0, [1.0], 900.0)
	var quarter := samples.size() / 4
	assert_int(_crossings(samples, samples.size() - quarter, samples.size())).is_greater(
		_crossings(samples, 0, quarter))


func _crossings(samples: PackedFloat32Array, from: int, to: int) -> int:
	var count := 0
	for i in range(from + 1, to):
		if signf(samples[i]) != signf(samples[i - 1]):
			count += 1
	return count


func test_noise_burst_is_deterministic_per_seed() -> void:
	var a := Synth.noise_burst(0.05, 30.0, 3)
	var b := Synth.noise_burst(0.05, 30.0, 3)
	assert_int(a.size()).is_equal(roundi(0.05 * Synth.MIX_RATE))
	assert_array(Array(a)).is_equal(Array(b))
	assert_float(_peak(a)).is_greater(0.1)


func test_mix_adds_with_offset_and_extends() -> void:
	var a := PackedFloat32Array([0.1, 0.1])
	var b := PackedFloat32Array([0.2, 0.2])
	var mixed := Synth.mix(a, b, 1, 0.5)
	assert_int(mixed.size()).is_equal(3)
	assert_float(mixed[0]).is_equal_approx(0.1, 0.0001)
	assert_float(mixed[1]).is_equal_approx(0.2, 0.0001)
	assert_float(mixed[2]).is_equal_approx(0.1, 0.0001)


func test_normalize_never_clips() -> void:
	var loud := PackedFloat32Array([0.0, 2.5, -3.0, 1.0])
	var normalized := Synth.normalize(loud, 0.8)
	assert_float(_peak(normalized)).is_equal_approx(0.8, 0.0001)


func test_drone_loops_seamlessly() -> void:
	var drone := Synth.drone(Synth.DRONE_LOOP_SECONDS)
	assert_int(drone.size()).is_equal(roundi(Synth.DRONE_LOOP_SECONDS * Synth.DRONE_MIX_RATE))
	assert_float(_peak(drone)).is_greater(0.1)
	# The sample after the last one is sample 0 again: the step across the seam must be no bigger
	# than the steps inside the buffer (a discontinuity would click on every loop).
	var max_step := 0.0
	for i in range(1, drone.size()):
		max_step = maxf(max_step, absf(drone[i] - drone[i - 1]))
	var seam := absf(drone[0] - drone[drone.size() - 1])
	assert_float(seam).is_less_equal(max_step * 1.05)


func test_wav_stream_is_16_bit_mono_pcm() -> void:
	var samples := Synth.tone(440.0, 0.1)
	var stream := Synth.to_stream(samples)
	assert_int(stream.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
	assert_int(stream.mix_rate).is_equal(Synth.MIX_RATE)
	assert_bool(stream.stereo).is_false()
	assert_int(stream.data.size()).is_equal(samples.size() * 2)
	assert_int(stream.loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)
	var looped := Synth.to_stream(samples, true)
	assert_int(looped.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(looped.loop_end).is_equal(samples.size())


func test_every_bank_sound_is_built_and_not_silent() -> void:
	for sound: StringName in SoundBank.NAMES:
		var stream := SoundBank.get_stream(sound)
		assert_object(stream).override_failure_message(String(sound)).is_not_null()
		var loud := 0
		for i in range(0, stream.data.size(), 2):
			if absi(stream.data.decode_s16(i)) > 1000:
				loud += 1
		assert_int(loud).override_failure_message(String(sound)).is_greater(10)


func test_loops_are_flagged_as_loops() -> void:
	assert_int(SoundBank.get_stream(&"ambient").loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(SoundBank.get_stream(&"tension").loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(SoundBank.get_stream(&"grab").loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)


func test_bank_caches_streams() -> void:
	assert_object(SoundBank.get_stream(&"grab")).is_same(SoundBank.get_stream(&"grab"))
	assert_object(SoundBank.get_stream(&"missing")).is_null()
