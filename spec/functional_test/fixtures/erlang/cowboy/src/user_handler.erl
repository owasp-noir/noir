%% REST handler — declares its verbs through allowed_methods/2.
-module(user_handler).
-behaviour(cowboy_rest).

-export([init/2, allowed_methods/2, content_types_provided/2, content_types_accepted/2]).
-export([to_json/2, from_json/2, delete_resource/2]).

init(Req, State) ->
    {cowboy_rest, Req, State}.

allowed_methods(Req, State) ->
    {[<<"GET">>, <<"PUT">>, <<"DELETE">>], Req, State}.

content_types_provided(Req, State) ->
    {[{<<"application/json">>, to_json}], Req, State}.

content_types_accepted(Req, State) ->
    {[{<<"application/json">>, from_json}], Req, State}.

to_json(Req, State) ->
    Id = cowboy_req:binding(id, Req),
    #{fields := Fields} = cowboy_req:match_qs([{fields, [], undefined}], Req),
    Token = cowboy_req:header(<<"x-api-token">>, Req),
    Body = jsx:encode(#{id => Id, fields => Fields, token => Token}),
    {Body, Req, State}.

from_json(Req0, State) ->
    {ok, _Body, Req} = cowboy_req:read_body(Req0),
    {true, Req, State}.

delete_resource(Req, State) ->
    {true, Req, State}.
