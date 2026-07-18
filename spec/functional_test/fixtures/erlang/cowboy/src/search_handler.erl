-module(search_handler).
-behaviour(cowboy_rest).

-export([init/2, allowed_methods/2]).

init(Req, State) ->
    {cowboy_rest, Req, State}.

%% A 100% match rate would be nice, but "GET" is all we allow here.
allowed_methods(Req, State) ->
    {[<<"GET">>], Req, State}.
