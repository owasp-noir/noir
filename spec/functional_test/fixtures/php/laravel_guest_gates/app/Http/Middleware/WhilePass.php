<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class WhilePass
{
    public function handle($request, Closure $next)
    {
        while ($this->shouldRetry()) {
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
