<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class ApiOnlyPass
{
    public function handle($request, Closure $next)
    {
        if ($request->is("api/*")) {
            if (! $request->user()) {
                return $next($request);
            }
            return $next($request);
        }
        abort_unless($request->user(), 401);
        return $next($request);
    }
}
