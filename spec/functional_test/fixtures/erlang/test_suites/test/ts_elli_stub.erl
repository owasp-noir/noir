%% Test stub for an elli callback; lives under test/ so it is never served.
-module(ts_elli_stub).
-behaviour(elli_handler).

-export([handle/2, handle_event/3]).

-include_lib("elli/include/elli.hrl").

handle(Req, _Args) ->
    handle(Req#req.method, elli_request:path(Req), Req).

handle('GET', [<<"elli-test-dir-only">>], _Req) ->
    {ok, [], <<"stub">>}.

handle_event(_Event, _Data, _Args) ->
    ok.
