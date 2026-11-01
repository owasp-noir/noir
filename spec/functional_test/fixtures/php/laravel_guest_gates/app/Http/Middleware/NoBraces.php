<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class NoBraces
{
    public function handle($request, Closure $next)
    {
        if ($request->user() && $request->user()->banned) abort(403);
        if (! $request->user()) abort(401);
        return $next($request);
    }
}
