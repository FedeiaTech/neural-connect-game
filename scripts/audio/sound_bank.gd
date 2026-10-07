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

const NAMES: Array[StringName] = [&"ambient", &"grab", &"release", &"blocked", &"tension", &"snap",
	&"chime", &"complete", &"star", &"ui_hover", &"ui_click"]
## Sounds that loop (the AudioDirector keeps one voice for each).
const LOOPS: Array[StringName] = [&"ambient", &"tension"]

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
	return null


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
