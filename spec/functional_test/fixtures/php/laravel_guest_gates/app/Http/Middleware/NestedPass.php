<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class NestedPass
{
    public function handle($request, Closure $next)
    {
        if ($request->routeIs("public.*")) {
            if (! $request->user()) {
                return $next($request);
            }
        }
        if (! $request->user()) {
            abort(401);
        }
        return $next($request);
    }
}
