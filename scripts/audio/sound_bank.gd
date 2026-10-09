class_name SoundBank
extends RefCounted
## The game's sounds as Synth recipes (SDD 5.4 audio): soft, sparse, bioluminescent. Each stream
## is rendered once and cached for the whole session (static), so repeated screens and restarts
## never re-synthesize. The AudioDirector renders them on a worker thread at startup (about 0.5 s
## of GDScript in total, the chord alone ~0.26 s), so the menu never hitches.
##
##   ambient   8 s seamless drone (A1, fifth, beating octave, faint swelling upper fifth), Music bus
##   grab      rising synaptic blip 620 -> 880 Hz
##   release   falling blip 880 -> 560 Hz
##   blocked   tiny soft tick (noise + high click) when a neuron hits something
##   tension   1 s loop, 330 Hz with a 6 Hz tremolo; its pitch and volume follow the tension
##   snap      noise burst plus a falling tone when a tension dendrite breaks
##   chime     glassy bell (fundamental + inharmonic 2.76x partial) when a crossing resolves
##   complete  arpeggiated A major chord with a long tail
##   star      bright bell ping (pitched up per star by the AudioDirector)
##   ui_hover  very soft high tick
##   ui_click  short rising blip
##   buzz      1 s loop: soft 100 Hz electric hum with harmonics and a crackle, while crossings exist
##   alarm     1 s loop: two-tone warble whose pitch and volume follow the lethal-wall proximity
##   explode   overload burst: low noise boom, crackle and a falling whine
##   link      ascending synaptic click: two ticks and a rising chirp (receptor link formed)
##   diseased_crack  1 s loop: wooden crackle over a thin 140 Hz buzz, rising with the strain of a
##                   diseased dendrite (T8.3)
##   diseased_snap   dry crack: noise burst, a falling split tone and embers
##   toxic_alarm  1 s loop: four short dry 1250 Hz beeps (contamination warning; not the warble)
##   toxic_clear  two ascending bell notes when the contamination is cleared
##   toxic_overload  HARD toxic (T8.6): sizzling yellow burst: noise, a falling whine over four
##                   squeezed 1250 Hz beeps and a crackle (not the lethal-wall explosion)
##   boss_stinger  boss intro hit: low swelling sub, a rising tritone sweep and an inharmonic gong
##   boss_fanfare  boss completion: fast rising C major arpeggio into a wide chord with bells
##   boss_hover    mission map: soft low-high double tick when a boss node is hovered
##   boss_press    mission map: deep thud with a rising swell when a boss node is pressed
##   unlink    small snap: noise tick and a falling chirp (receptor link broken; not a loss)

const NAMES: Array[StringName] = [&"ambient", &"grab", &"release", &"blocked", &"tension", &"snap",
	&"chime", &"complete", &"star", &"ui_hover", &"ui_click", &"buzz", &"alarm", &"explode",
	&"link", &"unlink", &"toxic_alarm", &"toxic_clear",
	&"diseased_crack", &"diseased_snap",
	&"toxic_overload", &"boss_stinger", &"boss_fanfare", &"boss_hover", &"boss_press"]
## Sounds that loop (the AudioDirector keeps one voice for each).
const LOOPS: Array[StringName] = [&"ambient", &"tension", &"buzz", &"alarm", &"toxic_alarm", &"diseased_crack"]

static var _cache: Dictionary[StringName, AudioStreamWAV] = {}


## Cached stream for a sound name, or null for an unknown name. Main thread only.
static func get_stream(sound: StringName) -> AudioStreamWAV:
	if _cache.has(sound):
		return _cache[sound]
	var stream := build(sound)
	if stream != null:
		_cache[sound] = stream
	return stream


static func is_built(sound: StringName) -> bool:
	return _cache.has(sound)


## Adds streams rendered elsewhere (e.g. on a worker thread) to the cache; existing ones win.
## Main thread only.
static func store(streams: Dictionary) -> void:
	for sound: StringName in streams:
		if not _cache.has(sound) and streams[sound] != null:
			_cache[sound] = streams[sound]


## Renders a sound without touching the cache: pure, safe to call from a worker thread.
static func build(sound: StringName) -> AudioStreamWAV:
	match sound:
		&"ambient":
			return Synth.to_stream(Synth.drone(Synth.DRONE_LOOP_SECONDS), true, Synth.DRONE_MIX_RATE)
		&"grab":
			return _one_shot(Synth.tone(620.0, 0.12, 0.004, 22.0, [1.0, 0.25], 880.0), 0.5)
		&"release":
			return _one_shot(Synth.tone(880.0, 0.14, 0.004, 18.0, [1.0, 0.25], 560.0), 0.45)
		&"blocked":
			var tick := Synth.mix(Synth.noise_burst(0.035, 90.0, 11), Synth.tone(1400.0, 0.03, 0.001, 80.0), 0, 0.5)
			return _one_shot(tick, 0.35)
		&"tension":
			return Synth.to_stream(Synth.normalize(
				Synth.loop_tone(330.0, 1.0, [1.0, 0.0, 0.18], 6.0, 0.35), 0.4), true)
		&"snap":
			var snap := Synth.mix(Synth.noise_burst(0.3, 18.0, 7),
				Synth.tone(900.0, 0.25, 0.001, 12.0, [1.0, 0.5], 160.0), 0, 0.8)
			return _one_shot(snap, 0.7)
		&"chime":
			return _one_shot(_bell(1046.5, 0.7, 5.0), 0.35)
		&"complete":
			return _one_shot(_chord([220.0, 277.18, 329.63, 440.0, 554.37], 0.07, 2.0), 0.6)
		&"star":
			return _one_shot(_bell(1318.5, 0.5, 7.0), 0.45)
		&"ui_hover":
			return _one_shot(Synth.tone(1760.0, 0.05, 0.003, 50.0), 0.18)
		&"ui_click":
			return _one_shot(Synth.tone(520.0, 0.09, 0.002, 30.0, [1.0, 0.3], 760.0), 0.35)
		&"buzz":
			var hum := Synth.loop_tone(100.0, 1.0, [1.0, 0.55, 0.35, 0.25, 0.15], 8.0, 0.25)
			return Synth.to_stream(Synth.normalize(Synth.mix(hum, Synth.crackle(1.0, 26, 31), 0, 0.45), 0.4), true)
		&"alarm":
			var low := Synth.loop_tone(660.0, 1.0, [1.0, 0.0, 0.3], 6.0, 0.9)
			var high := Synth.loop_tone(880.0, 1.0, [1.0, 0.0, 0.3], 6.0, 0.9)
			# The two tremolos run in opposite phase: a warble between the tones.
			var warble := PackedFloat32Array()
			warble.resize(low.size())
			for i in low.size():
				var t := float(i) / Synth.MIX_RATE
				var w := 0.5 + 0.5 * sin(TAU * 6.0 * t)
				warble[i] = low[i] * w + high[i] * (1.0 - w)
			return Synth.to_stream(Synth.normalize(warble, 0.35), true)
		&"explode":
			var boom := Synth.mix(Synth.noise_burst(0.7, 6.0, 13), Synth.tone(140.0, 0.7, 0.002, 5.0, [1.0, 0.6], 45.0), 0, 0.9)
			boom = Synth.mix(boom, Synth.crackle(0.5, 30, 17), 0, 0.5)
			boom = Synth.mix(boom, Synth.tone(1500.0, 0.5, 0.002, 7.0, [1.0, 0.3], 300.0), 0, 0.35)
			return _one_shot(boom, 0.85)
		&"link":
			var click := Synth.mix(Synth.tone(1200.0, 0.025, 0.001, 90.0), Synth.tone(1600.0, 0.025, 0.001, 90.0),
				roundi(0.045 * Synth.MIX_RATE), 0.9)
			click = Synth.mix(click, Synth.tone(700.0, 0.22, 0.004, 12.0, [1.0, 0.0, 0.25], 1400.0),
				roundi(0.07 * Synth.MIX_RATE), 0.8)
			return _one_shot(click, 0.45)
		&"unlink":
			var unlink := Synth.mix(Synth.noise_burst(0.08, 45.0, 23),
				Synth.tone(1300.0, 0.18, 0.001, 16.0, [1.0, 0.4], 320.0), 0, 0.7)
			return _one_shot(unlink, 0.45)
		&"toxic_alarm":
			return Synth.to_stream(Synth.normalize(_beeps(1250.0, 4, 0.11), 0.35), true)
		&"diseased_crack":
			var buzz := Synth.loop_tone(140.0, 1.0, [1.0, 0.45, 0.2], 11.0, 0.75)
			return Synth.to_stream(Synth.normalize(Synth.mix(buzz, Synth.crackle(1.0, 56, 41), 0, 0.9), 0.4), true)
		&"diseased_snap":
			var crack := Synth.mix(Synth.noise_burst(0.32, 16.0, 29),
				Synth.tone(1100.0, 0.22, 0.001, 14.0, [1.0, 0.5], 180.0), 0, 0.8)
			crack = Synth.mix(crack, Synth.tone(620.0, 0.2, 0.001, 18.0, [1.0, 0.3], 140.0), roundi(0.035 * Synth.MIX_RATE), 0.6)
			crack = Synth.mix(crack, Synth.crackle(0.4, 22, 53), 0, 0.5)
			return _one_shot(crack, 0.75)
		&"toxic_overload":
			var fizz := Synth.mix(Synth.noise_burst(0.55, 7.0, 61),
				Synth.tone(2400.0, 0.5, 0.002, 6.0, [1.0, 0.4], 260.0), 0, 0.8)
			fizz = Synth.mix(fizz, Synth.tone(110.0, 0.6, 0.002, 5.0, [1.0, 0.7], 40.0), 0, 0.8)
			for k in 4:
				fizz = Synth.mix(fizz, Synth.tone(1250.0, 0.05, 0.002, 40.0, [1.0, 0.35]),
					roundi((0.02 + 0.07 * k) * Synth.MIX_RATE), 0.6)
			fizz = Synth.mix(fizz, Synth.crackle(0.5, 36, 67), 0, 0.5)
			return _one_shot(fizz, 0.85)
		&"boss_stinger":
			var hit := Synth.tone(55.0, 1.6, 0.35, 1.6, [1.0, 0.6, 0.3], 41.0)
			hit = Synth.mix(hit, Synth.tone(196.0, 1.2, 0.5, 2.0, [1.0, 0.3, 0.2], 277.0), 0, 0.5)
			hit = Synth.mix(hit, Synth.tone(277.2, 1.2, 0.5, 2.0, [1.0, 0.3, 0.2], 392.0), 0, 0.45)
			hit = Synth.mix(hit, Synth.tone(110.0, 1.4, 0.01, 2.6, [1.0, 0.8, 0.5]), roundi(0.55 * Synth.MIX_RATE), 0.9)
			hit = Synth.mix(hit, _bell(164.8, 2.0, 1.8), roundi(0.55 * Synth.MIX_RATE), 0.55)
			hit = Synth.mix(hit, Synth.noise_burst(0.7, 5.0, 71), roundi(0.55 * Synth.MIX_RATE), 0.35)
			return _one_shot(hit, 0.9)
		&"boss_fanfare":
			var fan := PackedFloat32Array()
			var notes := [261.63, 329.63, 392.0, 523.25, 659.25]
			for k in notes.size():
				fan = Synth.mix(fan, Synth.tone(notes[k], 0.5, 0.004, 4.0, [1.0, 0.5, 0.25]),
					roundi(k * 0.09 * Synth.MIX_RATE), 0.7)
			var at := roundi(0.5 * Synth.MIX_RATE)
			for freq: float in [130.81, 261.63, 329.63, 392.0, 523.25, 783.99]:
				fan = Synth.mix(fan, Synth.tone(freq, 2.4, 0.02, 1.5, [1.0, 0.35, 0.15]), at, 0.55)
			fan = Synth.mix(fan, _bell(1046.5, 1.6, 3.5), at, 0.5)
			fan = Synth.mix(fan, _bell(1568.0, 1.4, 4.0), roundi(0.62 * Synth.MIX_RATE), 0.4)
			return _one_shot(fan, 0.7)
		&"boss_hover":
			var tick := Synth.mix(Synth.tone(330.0, 0.08, 0.003, 30.0, [1.0, 0.3]),
				Synth.tone(990.0, 0.08, 0.003, 30.0), roundi(0.045 * Synth.MIX_RATE), 0.8)
			return _one_shot(tick, 0.3)
		&"boss_press":
			var thud := Synth.mix(Synth.tone(95.0, 0.35, 0.002, 9.0, [1.0, 0.6], 50.0),
				Synth.tone(300.0, 0.4, 0.15, 5.0, [1.0, 0.2], 620.0), 0, 0.5)
			return _one_shot(Synth.mix(thud, Synth.noise_burst(0.1, 40.0, 73), 0, 0.4), 0.55)
		&"toxic_clear":
			var first := _bell(880.0, 0.5, 6.0)
			return _one_shot(Synth.mix(first, _bell(1318.5, 0.6, 6.0), roundi(0.1 * Synth.MIX_RATE), 0.9), 0.4)
	return null


## Seamless 1 s loop of `count` evenly spaced beeps at freq (a whole number of cycles per second),
## each `length` seconds long with short ramps so nothing clicks.
static func _beeps(freq: float, count: int, length: float) -> PackedFloat32Array:
	var total := Synth.MIX_RATE
	var samples := PackedFloat32Array()
	samples.resize(total)
	var slot := 1.0 / count
	var ramp := 0.012
	for i in total:
		var t := float(i) / Synth.MIX_RATE
		var local := fposmod(t, slot)
		var gate := clampf(minf(local, length - local) / ramp, 0.0, 1.0)
		var phase := TAU * freq * t
		samples[i] = (sin(phase) + 0.35 * sin(2.0 * phase) + 0.15 * sin(3.0 * phase)) * gate
	return samples


static func _one_shot(samples: PackedFloat32Array, peak: float) -> AudioStreamWAV:
	return Synth.to_stream(Synth.normalize(samples, peak))


## Bell: fundamental with a soft third partial plus an inharmonic 2.76x partial.
static func _bell(freq: float, duration: float, decay: float) -> PackedFloat32Array:
	var body := Synth.tone(freq, duration, 0.002, decay, [1.0, 0.0, 0.2])
	return Synth.mix(body, Synth.tone(freq * 2.76, duration, 0.002, decay * 1.8), 0, 0.3)


## Notes started stagger seconds apart, each ringing for duration with a slow decay.
static func _chord(freqs: Array, stagger: float, duration: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for i in freqs.size():
		var note := Synth.tone(freqs[i], duration, 0.01, 1.8, [1.0, 0.25])
		result = Synth.mix(result, note, roundi(i * stagger * Synth.MIX_RATE), 1.0)
	return result
