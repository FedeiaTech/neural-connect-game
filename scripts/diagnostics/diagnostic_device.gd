class_name DiagnosticDevice
extends RefCounted
## The environment block of the diagnostics report: renderer, GPU driver, audio output, display and
## OS. Every query is a plain engine call; values a platform does not provide are left out.


static func describe() -> String:
	var lines := PackedStringArray()
	lines.append("OS: %s %s | model=%s | cpus=%d | locale=%s" % [OS.get_name(), OS.get_version(),
		OS.get_model_name(), OS.get_processor_count(), OS.get_locale()])
	lines.append("Build: godot=%s | %s | app=%s | features: %s" % [
		Engine.get_version_info().get("string", "?"), "debug" if OS.is_debug_build() else "release",
		ProjectSettings.get_setting("application/config/version", "?"), _features()])
	lines.append("Renderer: %s / %s | adapter=%s | vendor=%s | api=%s | type=%s" % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
		RenderingServer.get_video_adapter_api_version(), _adapter_type()])
	lines.append("GPU limits: %s" % _gpu_limits())
	lines.append("Audio: mix_rate=%d Hz | output_latency=%.1f ms | device=%s | speaker_mode=%d | buses=%d" % [
		int(AudioServer.get_mix_rate()), AudioServer.get_output_latency() * 1000.0,
		AudioServer.get_output_device(), AudioServer.get_speaker_mode(), AudioServer.bus_count])
	lines.append("Display: screen=%s | refresh=%.1f Hz | dpi=%d | scale=%.2f | window=%s | safe_area=%s | vsync=%d" % [
		DisplayServer.screen_get_size(), DisplayServer.screen_get_refresh_rate(),
		DisplayServer.screen_get_dpi(), DisplayServer.screen_get_scale(), DisplayServer.window_get_size(),
		DisplayServer.get_display_safe_area(), DisplayServer.window_get_vsync_mode()])
	lines.append("Memory at start: static=%dMB | vram=%dMB | tex=%dMB | buf=%dMB" % [
		int(OS.get_static_memory_usage() / 1048576.0),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0),
		int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0)])
	return "\n".join(lines)


static func _features() -> String:
	var found := PackedStringArray()
	for feature in ["android", "mobile", "arm64", "web", "windows", "etc2", "astc"]:
		if OS.has_feature(feature):
			found.append(feature)
	return ",".join(found)


static func _adapter_type() -> String:
	var names := ["other", "integrated", "discrete", "virtual", "cpu"]
	var type := int(RenderingServer.get_video_adapter_type())
	return names[type] if type >= 0 and type < names.size() else str(type)


## Texture and buffer limits, only where a RenderingDevice exists (Vulkan, not the OpenGL renderer).
static func _gpu_limits() -> String:
	var device := RenderingServer.get_rendering_device()
	if device == null:
		return "not available (no RenderingDevice on this renderer)"
	return "max_texture_2d=%d | max_vertex_attribs=%d | max_framebuffer=%dx%d" % [
		device.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D),
		device.limit_get(RenderingDevice.LIMIT_MAX_VERTEX_INPUT_ATTRIBUTES),
		device.limit_get(RenderingDevice.LIMIT_MAX_FRAMEBUFFER_WIDTH),
		device.limit_get(RenderingDevice.LIMIT_MAX_FRAMEBUFFER_HEIGHT)]
