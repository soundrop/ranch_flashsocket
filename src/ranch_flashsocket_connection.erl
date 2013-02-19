-module(ranch_flashsocket_connection).
-export([
	transport/1
]).

-include("../include/flashsocket.hrl").

transport(Connection) ->
	{ok, Connection#flashsocket_connection.transport, Connection#flashsocket_connection.socket}.
