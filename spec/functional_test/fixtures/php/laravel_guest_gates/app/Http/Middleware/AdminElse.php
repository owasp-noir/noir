<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class AdminElse
{
    public function handle($request, Closure $next)
    {
        if (Auth::check() && Auth::user()->isAdmin()) {
            return $next($request);
        } else {
            abort(403);
        }
    }
}
