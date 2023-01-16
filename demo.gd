extends Control


var peer = ENetMultiplayerPeer.new()

func _ready():
	$Pinger.state_synced.connect(sync_state)


func start_server():
	peer.create_server(9081)
	multiplayer.set_multiplayer_peer(peer)


func start_client():
	peer.create_client("127.0.0.1", 9081)
	multiplayer.set_multiplayer_peer(peer)


func sync_state(state):
	$Label.text = ""
	for k in state:
		$Label.text += "%s: %s\n" % [k, state[k]]
