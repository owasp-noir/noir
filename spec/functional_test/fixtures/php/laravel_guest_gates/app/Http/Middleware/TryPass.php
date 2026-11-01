<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class TryPass
{
    public function handle($request, Closure $next)
    {
        try {
            if (! $request->user()) {
                return $next($request);
            }
        } finally {
        }
        abort(403);
    }
}
