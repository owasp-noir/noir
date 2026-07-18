%% Plain handler — branches on cowboy_req:method/1 instead of
%% declaring allowed_methods/2.
-module(user_collection_handler).
-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Req = handle(Method, Req0),
    {ok, Req, State}.

handle(<<"GET">>, Req0) ->
    #{page := Page, per_page := PerPage} =
        cowboy_req:match_qs([{page, int, 1}, {per_page, int, 20}], Req0),
    cowboy_req:reply(200, #{}, jsx:encode(#{page => Page, per_page => PerPage}), Req0);
handle(<<"POST">>, Req0) ->
    {ok, KeyValues, Req} = cowboy_req:read_urlencoded_body(Req0),
    cowboy_req:reply(201, #{}, jsx:encode(KeyValues), Req);
handle(_, Req0) ->
    cowboy_req:reply(405, Req0).
