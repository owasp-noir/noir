<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class MatchPass
{
    public function handle($request, Closure $next)
    {
        $public = match ($request->method()) { "GET" => true, default => false };
        if (! $request->user()) {
            return $next($request);
        }
        abort(401);
    }
}
