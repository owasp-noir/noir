-module(inline_handler).
-export([init/2]).

init(Req, State) ->
    {ok, Req, State}.
