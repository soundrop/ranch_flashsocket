-module(ranch_flashsocket_protocol).

-behaviour(ranch_protocol).
-export([start_link/4]).
-export([init/4]).


-include("flashsocket.hrl").

-record(state, {
	listener :: pid(),
	connection :: #flashsocket_connection{},
	handler :: module(),
	opts :: any(),
	messages = undefined :: undefined | {atom(), atom(), atom()},
	buffer = <<>> :: binary()
}).

-spec start_link(pid(), inet:socket(), module(), any()) -> {ok, pid()}.
start_link(ListenerPid, Socket, Transport, Opts) ->
	Pid = spawn_link(?MODULE, init, [ListenerPid, Socket, Transport, Opts]),
	{ok, Pid}.


%% @private
-spec init(pid(), inet:socket(), module(), any()) -> ok.
init(ListenerPid, Socket, Transport, Opts) ->
	ok = ranch:accept_ack(ListenerPid),
	Connection = #flashsocket_connection{
		socket = Socket,
		transport = Transport
	},
	case lists:keyfind(handler, 1, Opts) of
		{_, Handler} ->
			handler_init(#state{
				listener = ListenerPid,
				connection = Connection,
				handler = Handler,
				opts = Opts
			});
		_ ->
			exit(nohandler)
	end.

%% @private
-spec terminate(#state{}) -> ok.
terminate(State) ->
	Connection = State#state.connection,
	Transport = Connection#flashsocket_connection.transport,
	Socket = Connection#flashsocket_connection.socket,
	Transport:close(Socket),
	ok.


%% @private
-spec handler_init(#state{}) -> closed.
handler_init(State) ->
	Handler = State#state.handler,
	Connection = State#state.connection,
	Opts = State#state.opts,
	Transport = Connection#flashsocket_connection.transport,
	try Handler:flashsocket_init(Transport:name(), Connection, Opts) of
		{ok, HandlerState} ->
			flashsocket_before_loop(State#state{messages = Transport:messages()}, HandlerState);
		shutdown ->
			terminate(State)
	catch Class:Reason ->
		error_logger:error_msg(
			"** Flashsocket Handler ~p terminating in ~p/~p~n"
			"   for the reason ~p:~p~n** Options were ~p~n"
			"** Stacktrace: ~p~n~n",
			[Handler, flashsocket_init, 3, Class, Reason, Opts, erlang:get_stacktrace()])
	end.

%% @private
-spec handler_call(#state{}, any(), atom(), binary()) -> closed.
handler_call(State, HandlerState, Callback, Message) ->
	Handler = State#state.handler,
	try Handler:Callback(Message, HandlerState) of
		{ok, HandlerState2} ->
			flashsocket_data(State, HandlerState2);
		{reply, Payload, HandlerState2} ->
			case flashsocket_send(Payload, State) of
				{error, Reason} ->
					handler_terminate(State, HandlerState2, {error, Reason});
				_ ->
					flashsocket_data(State, HandlerState2)
			end;
		{shutdown, HandlerState2} ->
			flashsocket_close(State, HandlerState2, {normal, shutdown})
	catch Class:Reason ->
		error_logger:error_msg(
			"** Flashsocket Handler ~p terminating in ~p/~p~n"
			"   for the reason ~p:~p~n** Message was ~p~n"
			"** Options were ~p~n** Handler state was ~p~n"
			"** Stacktrace: ~p~n~n",
			[Handler, Callback, 2, Class, Reason, Message, State#state.opts,
			 HandlerState, erlang:get_stacktrace()]),
		flashsocket_close(State, HandlerState, {error, handler})
	end.

%% @private
-spec handler_terminate(#state{}, any(), atom() | {atom(), atom()}) -> closed.
handler_terminate(State, HandlerState, TerminateReason) ->
	Handler = State#state.handler,
	try
		Handler:flashsocket_terminate(TerminateReason, HandlerState)
	catch Class:Reason ->
		error_logger:error_msg(
			"** Flashsocket Handler ~p terminating in ~p/~p~n"
			"   for the reason ~p:~p~n** Initial reason was ~p~n"
			"** Options were ~p~n** Handler state was ~p~n"
			"** Stacktrace: ~p~n~n",
			[Handler, flashsocket_terminate, 2, Class, Reason, TerminateReason, State#state.opts,
			 HandlerState, erlang:get_stacktrace()])
	end,
	terminate(State),
	closed.


%% @private
-spec flashsocket_before_loop(#state{}, any()) -> closed.
flashsocket_before_loop(State, HandlerState) ->
	Connection = State#state.connection,
	Transport = Connection#flashsocket_connection.transport,
	Socket = Connection#flashsocket_connection.socket,
	Transport:setopts(Socket, [{active, once}]),
	flashsocket_loop(State, HandlerState).

%% @private
-spec flashsocket_loop(#state{}, any()) -> closed.
flashsocket_loop(State = #state{messages = {OK, Closed, Error}}, HandlerState) ->
	Connection = State#state.connection,
	Socket = Connection#flashsocket_connection.socket,
	receive
		{OK, Socket, Data} ->
			Buffer = State#state.buffer,
			flashsocket_data(State#state{buffer = <<Buffer/binary, Data/binary>>}, HandlerState);
		{Closed, Socket} ->
			handler_terminate(State, HandlerState, {error, closed});
		{Error, Socket, Reason} ->
			handler_terminate(State, HandlerState, {error, Reason});
		Message ->
			handler_call(State, HandlerState, flashsocket_info, Message)
	end.

%% @private
-spec flashsocket_data(#state{}, any()) -> ok.
flashsocket_data(State, HandlerState) ->
	case extract_frame(State#state.buffer) of
		{Payload, Rest} ->
			handler_call(State#state{buffer = Rest}, HandlerState, flashsocket_handle, {text, Payload});
		_ ->
			flashsocket_before_loop(State, HandlerState)
	end.

%% @private
-spec flashsocket_close(#state{}, any(), {atom(), atom()}) -> closed.
flashsocket_close(State, HandlerState, Reason) ->
	handler_terminate(State, HandlerState, Reason).

%% @private
flashsocket_send({text, Payload}, State) ->
	Connection = State#state.connection,
	Transport = Connection#flashsocket_connection.transport,
	Socket = Connection#flashsocket_connection.socket,
	Transport:send(Socket, [Payload, 0]).


%% @private
extract_frame(Binary) ->
	extract_frame(Binary, 0, byte_size(Binary)).

%% @private
extract_frame(Binary, Offset, Length) ->
	case Binary of
		<<Frame:Offset/binary, 0, Rest/binary>> ->
			{Frame, Rest};
		_ when Offset < Length ->
			extract_frame(Binary, Offset + 1, Length);
		_ ->
			Binary
	end.
