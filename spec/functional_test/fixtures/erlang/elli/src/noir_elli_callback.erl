%% Elli routes by pattern-matching the method and split path in the
%% handle/3 clause heads.
-module(noir_elli_callback).
-behaviour(elli_handler).

-export([handle/2, handle_event/3]).

-include_lib("elli/include/elli.hrl").

handle(Req, _Args) ->
    handle(Req#req.method, elli_request:path(Req), Req).

handle('GET', [], _Req) ->
    {ok, [], <<"index">>};

handle('GET', [<<"hello">>, <<"world">>], _Req) ->
    {ok, [], <<"Hello World!">>};

handle('GET', [<<"users">>], Req) ->
    Page = elli_request:get_arg(<<"page">>, Req, <<"1">>),
    {ok, [], Page};

handle('POST', [<<"users">>], Req) ->
    Name = elli_request:post_arg(<<"name">>, Req),
    Token = elli_request:get_header(<<"X-Auth-Token">>, Req),
    {201, [], <<Name/binary, Token/binary>>};

handle('GET', [<<"users">>, Id], _Req) ->
    {ok, [], Id};

handle('DELETE', [<<"users">>, Id], _Req) ->
    {204, [], Id};

handle('GET', [<<"static">> | _], _Req) ->
    {ok, [], <<"static">>};

handle(_, _, _Req) ->
    {404, [], <<"Not Found">>}.

handle_event(_Event, _Data, _Args) ->
    ok.
