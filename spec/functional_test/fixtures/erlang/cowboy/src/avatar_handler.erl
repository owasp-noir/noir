-module(avatar_handler).
-behaviour(cowboy_rest).

-export([init/2, allowed_methods/2]).

init(Req, State) ->
    {cowboy_rest, Req, State}.

allowed_methods(Req, State) ->
    {[<<"GET">>, <<"POST">>], Req, State}.
