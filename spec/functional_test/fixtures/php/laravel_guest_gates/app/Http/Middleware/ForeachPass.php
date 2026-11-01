<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class ForeachPass
{
    public function handle($request, Closure $next)
    {
        foreach ($this->optional as $pattern) {
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
