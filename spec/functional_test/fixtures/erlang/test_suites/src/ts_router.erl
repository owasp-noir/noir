%% Cowboy dispatch table with an EUnit block inside the source module.
-module(ts_router).

-export([dispatch/0]).

dispatch() ->
    cowboy_router:compile([
        {'_', [
            {"/real", ts_handler, []}
        ]}
    ]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

compile_test_() ->
    Tests = [
        {"/ifdef-test-only", ts_handler, []},
        {"/nested/:id", ts_handler, []}
    ],
    -ifdef(DEBUG).
    {"/ifdef-nested-test-only", ts_handler, []},
    -endif.
    [?_assert(is_list(Tests))].
-else.
%% The branch compiled without TEST is production code.
else_branch() ->
    cowboy_router:compile([
        {'_', [
            {"/else-branch", ts_handler, []}
        ]}
    ]).
-endif.

after_ifdef() ->
    cowboy_router:compile([
        {'_', [
            {"/after-ifdef", ts_handler, []}
        ]}
    ]).
