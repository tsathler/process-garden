extends RefCounted
class_name ProcessSelector

const SnapshotParserScript = preload("res://scripts/snapshot_parser.gd")
const ACTIVITY_BAND_PERCENT := 5.0
const MAX_CPU_PERCENT := 100.0
const MAX_VISIBLE_CREATURES := 30


func select_processes(
	processes: Array[Dictionary], selected_identities: Array, limit: int = MAX_VISIBLE_CREATURES
) -> Array[Dictionary]:
	var selected_lookup: Dictionary = {}
	for identity in selected_identities:
		selected_lookup[str(identity)] = true

	var seen: Dictionary = {}
	var candidates: Array[Dictionary] = []
	for process in processes:
		var identity := SnapshotParserScript.identity_key(process)
		if seen.has(identity):
			continue
		seen[identity] = true

		var activity := _activity_percent(process)
		candidates.append(
			{
				"identity": identity,
				"pid": int(process["pid"]),
				"create_time": float(process["create_time"]),
				"activity_band": int(floor(activity / ACTIVITY_BAND_PERCENT)),
				"activity": activity,
				"memory_rss_bytes": int(process["memory_rss_bytes"]),
				"is_selected": selected_lookup.has(identity),
				"process": process,
			}
		)

	candidates.sort_custom(_candidate_precedes)
	var selected: Array[Dictionary] = []
	var selection_size := mini(mini(maxi(limit, 0), MAX_VISIBLE_CREATURES), candidates.size())
	for index in range(selection_size):
		selected.append(candidates[index]["process"])
	return selected


func _activity_percent(process: Dictionary) -> float:
	if int(process["pid"]) == 0 or process["cpu_percent"] == null:
		return 0.0
	var cpu := float(process["cpu_percent"])
	if not is_finite(cpu) or cpu < 0.0:
		return 0.0
	return clampf(cpu, 0.0, MAX_CPU_PERCENT)


func _candidate_precedes(left: Dictionary, right: Dictionary) -> bool:
	if left["activity_band"] != right["activity_band"]:
		return left["activity_band"] > right["activity_band"]
	if left["is_selected"] != right["is_selected"]:
		return left["is_selected"]
	if left["activity"] != right["activity"]:
		return left["activity"] > right["activity"]
	if left["memory_rss_bytes"] != right["memory_rss_bytes"]:
		return left["memory_rss_bytes"] > right["memory_rss_bytes"]
	if left["pid"] != right["pid"]:
		return left["pid"] < right["pid"]
	return left["create_time"] < right["create_time"]
