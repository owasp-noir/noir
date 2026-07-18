%% No allowed_methods/2 and no cowboy_req:method/1 match — the verb is
%% not statically resolvable, so this route falls back to "ANY".
-module(health_handler).
-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, State) ->
    Req = cowboy_req:reply(200, #{}, <<"ok">>, Req0),
    {ok, Req, State}.
