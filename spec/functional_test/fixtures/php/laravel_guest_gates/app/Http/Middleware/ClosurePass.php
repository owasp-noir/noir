<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class ClosurePass
{
    public function handle($request, Closure $next)
    {
        $optional = function () use ($request, $next) {
            if (! $request->user()) {
                return $next($request);
            }
        };
        if (! $request->user()) {
            abort(401);
        }
        return $next($request);
    }
}
