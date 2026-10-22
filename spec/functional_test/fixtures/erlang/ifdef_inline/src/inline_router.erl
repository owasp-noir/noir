%% A one-line `-ifdef(TEST). ... -endif.` must not leave the mask open for
%% the rest of the module.
-module(inline_router).

-export([dispatch/0]).

-ifdef(TEST). -include_lib("eunit/include/eunit.hrl"). -endif.

dispatch() ->
    cowboy_router:compile([
        {'_', [
            {"/after-inline", inline_handler, []}
        ]}
    ]).

-ifndef(TEST).
prod_branch() ->
    cowboy_router:compile([
        {'_', [
            {"/ifndef-branch", inline_handler, []}
        ]}
    ]).
-else.
%% The branch of -ifndef(TEST). compiled with TEST is test-only.
test_branch() ->
    cowboy_router:compile([
        {'_', [
            {"/ifndef-else-test-only", inline_handler, []}
        ]}
    ]).
-endif.

-ifdef(TEST). helper() -> {"/one-line-test-only", inline_handler, []}. -endif.

after_all() ->
    cowboy_router:compile([
        {'_', [
            {"/after-all", inline_handler, []}
        ]}
    ]).

-ifdef(TEST).
compile_test_() ->
    {"/multi-line-test-only", inline_handler, []}.
-endif.
