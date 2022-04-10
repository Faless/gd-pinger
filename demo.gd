extends Control


var peer = NetworkedMultiplayerENet.new()

func _ready():
	$Pinger.connect("sync_state", self, "sync_state")


func start_server():
	peer.create_server(9081)
	multiplayer.set_network_peer(peer)


func start_client():
	peer.create_client("127.0.0.1", 9081)
	multiplayer.set_network_peer(peer)


func sync_state(state):
	$Label.text = ""
	for k in state:
		$Label.text += "%s: %s\n" % [k, state[k]]
