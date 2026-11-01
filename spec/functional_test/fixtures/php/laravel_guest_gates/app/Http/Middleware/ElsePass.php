<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class ElsePass
{
    public function handle($request, Closure $next)
    {
        if ($request->is("admin/*")) {
            abort_unless($request->user(), 401);
        } else {
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
