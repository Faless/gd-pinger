extends Node

# Simple class that keeps track of ping results, and provide average ping.
# Could potentially calculate jitter, etc.
class PingInfo:

	# The number of samples to track
	const SIZE = 21

	var samples = PackedInt32Array()
	var pos = 0

	func _init():
		samples.resize(SIZE)
		for i in range(0, SIZE):
			samples[i] = 0

	func get_average():
		var val = 0
		for s in samples:
			val += s
		return 0 if val == 0 else val / SIZE

	func set_next(val):
		samples[pos] = val
		pos += 1
		if pos >= SIZE:
			pos = 0

# Called reguarly checked server (and checked clients as a result of RPC).
# Connect to this to get ping updates in the form:
# {
#    PEER_ID: PING
# }
signal state_synced(state)

@export var active = false
@export var ping_interval = 100
@export var sync_interval = 1000

# (ping_interval * ping_history) / 2 = maximum ping
@export var ping_history = 10 :
	set(value):
		if value < 1:
			return
		ping_history = value
		clear_pings()


var _clients := {}
var _state := {}
var _last_ping := 0
var _pings := []
var _last_sync := 0

func _init() -> void:
	clear_pings()


func _ready() -> void:
	multiplayer.peer_connected.connect(_add_peer)
	multiplayer.peer_disconnected.connect(_del_peer)


func _exit_tree() -> void:
	multiplayer.peer_connected.disconnect(_add_peer)
	multiplayer.peer_disconnected.disconnect(_del_peer)


func _process(delta: float) -> void:
	if not active or not multiplayer.has_multiplayer_peer() or \
		multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED \
		or not multiplayer.is_server():
		return

	var now = Time.get_ticks_msec()
	if sync_interval > 0 and now >= _last_sync + sync_interval:
		sync_state()
		_last_sync = now
	if now >= _pings[_last_ping] + ping_interval:
		_last_ping += 1
		if _last_ping == ping_history:
			_last_ping = 0
		_pings[_last_ping] = now
		_ping.rpc(now)


func clear_pings() -> void:
	_last_ping = 0
	_pings.resize(ping_history)
	for i in range(0, ping_history):
		_pings[i] = 0


func _add_peer(id: int) -> void:
	_clients[id] = PingInfo.new()


func _del_peer(id: int) -> void:
	_clients.erase(id)


@rpc
func _ping(time: int) -> void:
	_pong.rpc_id(1, time)


@rpc("any_peer")
func _pong(time: int) -> void:
	if not multiplayer.is_server():
		return
	var id = multiplayer.get_remote_sender_id()
	if not _clients.has(id):
		return

	var now = Time.get_ticks_msec()
	var last = _last_ping
	var found = ping_history * ping_interval

	for i in range(0, ping_history):
		last += 1
		if last == ping_history:
			last = 0
		if time == _pings[last]:
			found = _pings[last]
			break

	_clients[id].set_next((now - found) / 2)


func sync_state() -> void:
	if not active or not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return

	_state = {}
	for k in _clients:
		_state[k] = _clients[k].get_average()
	_sync_state.rpc(_state)
	state_synced.emit(_state)


@rpc
func _sync_state(state: Dictionary) -> void:
	_state = {}
	for k in state:
		if typeof(k) != TYPE_INT or typeof(state[k]) != TYPE_INT:
			continue
		_state[k] = state[k]
	state_synced.emit(_state)


func get_peer_latency(id: int) -> int:
	if not _state.has(id):
		return -1
	return _state[id]
