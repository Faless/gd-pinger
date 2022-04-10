extends Node

# Simple class that keeps track of ping results, and provide average ping.
# Could potentially calculate jitter, etc.
class PingInfo:

	# The number of samples to track
	const SIZE = 21

	var samples = PoolIntArray()
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

# Called reguarly on server (and on clients as a result of RPC).
# Connect to this to get ping updates in the form:
# {
#    PEER_ID: PING
# }
signal sync_state(state)

export var active = false
export var ping_interval = 100
export var sync_interval = 1000
export var ping_history = 10 setget set_ping_history # (ping_interval * ping_history) / 2 = maximum ping

var _clients = {}
var _state = {}
var _last_ping = 0
var _pings = []
var _last_sync = 0

func set_ping_history(val):
	if val < 1:
		return
	_last_ping = 0
	_pings.resize(val)
	for i in range(0, val):
		_pings[i] = 0
	ping_history = val


func _init():
	set_ping_history(ping_history)


func _ready():
	multiplayer.connect("network_peer_connected", self, "_add_peer")
	multiplayer.connect("network_peer_disconnected", self, "_del_peer")


func _exit_tree():
	multiplayer.disconnect("network_peer_connected", self, "_add_peer")
	multiplayer.disconnect("network_peer_disconnected", self, "_del_peer")


func _add_peer(id):
	_clients[id] = PingInfo.new()


func _del_peer(id):
	_clients.erase(id)


func _process(delta):
	if not active or not multiplayer.has_network_peer() or \
		multiplayer.network_peer.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_CONNECTED \
		or not multiplayer.is_network_server():
		return

	var now = OS.get_ticks_msec()
	if sync_interval > 0 and now >= _last_sync + sync_interval:
		sync_state()
		_last_sync = now
	if now >= _pings[_last_ping] + ping_interval:
		_last_ping += 1
		if _last_ping == ping_history:
			_last_ping = 0
		_pings[_last_ping] = now
		rpc("_ping", now)


puppet func _ping(time):
	if typeof(time) != TYPE_INT: return
	rpc_id(1, "_pong", time)

master func _pong(time):
	if typeof(time) != TYPE_INT: return
	var id = multiplayer.get_rpc_sender_id()
	if not _clients.has(id):
		return

	var now = OS.get_ticks_msec()
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

func sync_state():
	if not active or not multiplayer.has_network_peer() or not multiplayer.is_network_server():
		return

	_state = {}
	for k in _clients:
		_state[k] = _clients[k].get_average()
	rpc("_sync_state", _state)
	emit_signal("sync_state", _state)

puppet func _sync_state(state):
	if typeof(state) != TYPE_DICTIONARY: return
	_state = {}
	for k in state:
		if typeof(k) != TYPE_INT or typeof(state[k]) != TYPE_INT:
			continue
		_state[k] = state[k]
	emit_signal("sync_state", _state)

func get_peer_latency(id):
	if not _state.has(id):
		return -1
	return _state[id]
