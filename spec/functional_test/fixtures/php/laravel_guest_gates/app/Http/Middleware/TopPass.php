<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class TopPass
{
    public function handle($request, Closure $next)
    {
        $user = $request->user();
        if (! $user || $user->two_factor_confirmed_at) {
            return $next($request);
        }
        abort(403);
    }
}
