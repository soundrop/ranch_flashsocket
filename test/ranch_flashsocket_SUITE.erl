-module(ranch_flashsocket_SUITE).

-include_lib("common_test/include/ct.hrl").
-export([
	all/0,
	init_per_suite/1,
	end_per_suite/1,
	init_per_testcase/2,
	end_per_testcase/2
]).

-export([
	test/1
]).


all() ->
	[test].

init_per_suite(Config) ->
	Config.

end_per_suite(_Config) ->
	ok.

init_per_testcase(_Case, Config) ->
	Config.

end_per_testcase(_Case, _Config) ->
	ok.

%% Tests
test(_Config) ->
	ok.
