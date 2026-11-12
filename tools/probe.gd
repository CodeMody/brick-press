extends SceneTree
# Throwaway probe — namespace-qualified enum access check.

func _init() -> void:
	var w = AudioStreamWAV.new()
	var t = AudioStreamWAV.Format.FORMAT_PCM   # members live under the enum namespace in 4.4+
	w.format = t
	print("set ok, format = ", w.format, " sample_rate = ", w.sample_rate)
	quit(0)
