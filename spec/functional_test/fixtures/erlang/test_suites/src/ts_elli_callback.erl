-module(ts_elli_callback).
-behaviour(elli_handler).

-export([handle/2, handle_event/3]).

-include_lib("elli/include/elli.hrl").

handle(Req, _Args) ->
    handle(Req#req.method, elli_request:path(Req), Req).

handle('GET', [<<"ping">>], _Req) ->
    {ok, [], <<"pong">>};

-ifdef(TEST).
handle('GET', [<<"elli-ifdef-test-only">>], _Req) ->
    {ok, [], <<"test">>};
-endif.

handle('GET', [<<"after-ifdef">>], _Req) ->
    {ok, [], <<"ok">>}.

handle_event(_Event, _Data, _Args) ->
    ok.
