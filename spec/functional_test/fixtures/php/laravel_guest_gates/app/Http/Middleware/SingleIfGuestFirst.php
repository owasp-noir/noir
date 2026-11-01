<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class SingleIfGuestFirst
{
    public function handle($request, Closure $next)
    {
        if (! Auth::check() || ! Auth::user()->isAdmin()) {
            abort(403);
        }
        return $next($request);
    }
}
