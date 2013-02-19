-module(ranch_flashsocket_handler).

-type opts() :: any().
-type state() :: any().
-type connection() :: term().
-type terminate_reason() :: {normal, shutdown}
	| {normal, timeout}
	| {error, closed}
	| {remote, closed}
	| {error, atom()}.

-callback flashsocket_init(atom(), connection(), opts())
	-> {ok, state()}
	%| {ok, state(), hibernate}
	%| {ok, state(), timeout()}
	%| {ok, state(), timeout(), hibernate}
	| shutdown.
-callback flashsocket_handle(binary(), State)
	-> {ok, State}
	%| {ok, State, hibernate}
	| {reply, binary(), State}
	%| {reply, binary(), State, hibernate}
	| {shutdown, State}
	when State::state().
-callback flashsocket_info(any(), State)
	-> {ok, State}
	%| {ok, State, hibernate}
	| {reply, binary(), State}
	%| {reply, binary(), State, hibernate}
	| {shutdown, State}
	when State::state().
-callback flashsocket_terminate(terminate_reason(), state())
	-> ok.
