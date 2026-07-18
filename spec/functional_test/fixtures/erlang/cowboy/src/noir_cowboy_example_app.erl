%% @doc Cowboy application callback — builds the dispatch table.
-module(noir_cowboy_example_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/", hello_handler, []},
            {"/health", health_handler, []},
            {"/users", user_collection_handler, []},
            {"/users/:id", user_handler, []},
            {"/users/:id/avatar", [{id, int}], avatar_handler, []},
            {<<"/search">>, search_handler, []},
            {"/static/[...]", cowboy_static, {priv_dir, noir_cowboy_example, "static"}}
        ]}
    ]),
    {ok, _} = cowboy:start_clear(http_listener,
        [{port, 8080}],
        #{env => #{dispatch => Dispatch}}
    ),
    noir_cowboy_example_sup:start_link().

stop(_State) ->
    ok = cowboy:stop_listener(http_listener).
