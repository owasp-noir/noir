%% Common Test suite: starts a throwaway listener on a dispatch table that a
%% deployed node never serves.
-module(ts_SUITE).
-compile(export_all).

init_dispatch(_) ->
    cowboy_router:compile([
        {"localhost", [
            {"/", ts_handler, []},
            {"/suite-only/:key", ts_handler, []}
        ]}
    ]).
