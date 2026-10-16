%% EUnit module that lives beside the source it exercises.
-module(ts_router_tests).
-include_lib("eunit/include/eunit.hrl").

compile_test() ->
    cowboy_router:compile([
        {'_', [
            {"/eunit-only", ts_handler, []}
        ]}
    ]).
