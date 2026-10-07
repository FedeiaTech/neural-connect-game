class_name Synth
extends RefCounted
## Tiny offline synthesizer (SDD 5.4 audio, 8.8: no audio files). Pure functions that render mono
## float PCM (-1..1) and pack it into 16-bit AudioStreamWAV resources. SoundBank composes them
## into the game's sounds; nothing here touches nodes or the AudioServer.
##
## Building blocks: tone() (sine plus harmonics, optional glide, attack and exponential decay,
## short release so nothing clicks), noise_burst() (soft low-passed noise), mix(), normalize(),
## loop_tone() and drone() (seamless loops: every frequency fits a whole number of cycles in the
## loop length), to_stream().

const MIX_RATE := 22050
## The ambient drone only has low partials, so a lower rate halves its size and build time.
const DRONE_MIX_RATE := 11025
const DRONE_LOOP_SECONDS := 8.0
## Fade applied to the last samples of a one-shot so it never ends on a click.
const RELEASE_SECONDS := 0.012


## Sine tone. harmonics: relative amplitudes of partials 1, 2, 3... (normalized by their sum).
## The frequency glides linearly from freq to glide_to (when > 0). Envelope: linear attack, then
## exp(-decay * t), and a short release at the very end.
static func tone(freq: float, duration: float, attack := 0.005, decay := 6.0,
		harmonics: Array = [1.0], glide_to := 0.0, rate := MIX_RATE) -> PackedFloat32Array:
	var count := roundi(duration * rate)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var total := 0.0
	for h: float in harmonics:
		total += absf(h)
	if total <= 0.0 or count == 0:
		return samples
	var release := maxi(roundi(RELEASE_SECONDS * rate), 1)
	var end_freq := glide_to if glide_to > 0.0 else freq
	var phase := 0.0
	for i in count:
		var t := float(i) / rate
		var f := lerpf(freq, end_freq, float(i) / count)
		var value := 0.0
		for k in harmonics.size():
			value += harmonics[k] * sin(phase * (k + 1))
		var envelope := minf(t / maxf(attack, 0.0001), 1.0) * exp(-decay * t)
		envelope *= minf(float(count - 1 - i) / release, 1.0)
		samples[i] = value / total * envelope
		phase = fmod(phase + TAU * f / rate, TAU * 64.0)
	return samples


## Soft noise burst: white noise from a seeded generator, gently low-passed, decaying as
## exp(-decay * t). Deterministic for a given seed.
static func noise_burst(duration: float, decay: float, seed: int, rate := MIX_RATE) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var count := roundi(duration * rate)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var smooth := 0.0
	var release := maxi(roundi(RELEASE_SECONDS * rate), 1)
	for i in count:
		smooth = lerpf(smooth, rng.randf_range(-1.0, 1.0), 0.35)
		var envelope := exp(-decay * float(i) / rate) * minf(float(count - 1 - i) / release, 1.0)
		samples[i] = smooth * 1.6 * envelope
	return samples


## a plus b * gain, with b starting offset samples later; the result is as long as needed.
static func mix(a: PackedFloat32Array, b: PackedFloat32Array, offset := 0, gain := 1.0) -> PackedFloat32Array:
	var result := a.duplicate()
	var needed := offset + b.size()
	if result.size() < needed:
		var old := result.size()
		result.resize(needed)
		for i in range(old, needed):
			result[i] = 0.0
	for j in b.size():
		result[offset + j] += b[j] * gain
	return result


## Scales samples so the loudest one reaches peak (unchanged when silent).
static func normalize(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var loudest := 0.0
	for s in samples:
		loudest = maxf(loudest, absf(s))
	if loudest <= 0.0:
		return samples
	var result := samples.duplicate()
	var k := peak / loudest
	for i in result.size():
		result[i] *= k
	return result


## Steady looping tone of seconds length with a tremolo. For a seamless loop, freq * seconds and
## tremolo_hz * seconds must be whole numbers.
static func loop_tone(freq: float, seconds: float, harmonics: Array = [1.0], tremolo_hz := 0.0,
		tremolo_depth := 0.0, rate := MIX_RATE) -> PackedFloat32Array:
	var count := roundi(seconds * rate)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var total := 0.0
	for h: float in harmonics:
		total += absf(h)
	for i in count:
		var t := float(i) / rate
		var value := 0.0
		for k in harmonics.size():
			value += harmonics[k] * sin(TAU * freq * (k + 1) * t)
		var tremolo := 1.0 - tremolo_depth * (0.5 + 0.5 * sin(TAU * tremolo_hz * t))
		samples[i] = value / total * tremolo
	return samples


## Electric crackle (seamless loop of seconds length): count tiny decaying noise ticks at seeded
## random times, each fully inside the loop so the end meets the start in silence.
static func crackle(seconds: float, count: int, seed: int, rate := MIX_RATE) -> PackedFloat32Array:
	var total := roundi(seconds * rate)
	var samples := PackedFloat32Array()
	samples.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tick := roundi(0.012 * rate)
	for k in count:
		var start := rng.randi_range(0, maxi(total - tick - 1, 0))
		var gain := rng.randf_range(0.3, 1.0)
		for i in tick:
			var envelope := exp(-float(i) / (tick * 0.22))
			samples[start + i] += rng.randf_range(-1.0, 1.0) * gain * envelope
	return samples


## Ambient drone (seamless loop): a low A with a fifth, a slightly detuned octave that beats
## slowly, and a faint upper fifth that swells twice per loop. All frequencies are multiples of
## 1 / seconds (0.125 Hz for 8 s), so the end meets the start.
static func drone(seconds: float, rate := DRONE_MIX_RATE) -> PackedFloat32Array:
	var count := roundi(seconds * rate)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var base := 55.0
	for i in count:
		var t := float(i) / rate
		var swell := 0.5 + 0.5 * sin(TAU * 2.0 * t / seconds)
		var breath := 0.8 + 0.2 * sin(TAU * t / seconds)
		var value := 0.5 * sin(TAU * base * t) \
			+ 0.25 * sin(TAU * base * 1.5 * t) * breath \
			+ 0.28 * sin(TAU * (base * 2.0 + 0.125) * t) \
			+ 0.08 * sin(TAU * base * 3.0 * t) * swell
		samples[i] = value
	return normalize(samples, 0.6)


## Packs samples as a 16-bit mono AudioStreamWAV, optionally looping over the whole buffer.
static func to_stream(samples: PackedFloat32Array, loop := false, rate := MIX_RATE) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
