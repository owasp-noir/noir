<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class ConfigGuestPass
{
    public function handle($request, Closure $next)
    {
        if (config("app.guest_mode")) {
            if (! $request->user()) {
                return $next($request);
            }
        }
        if (! $request->user()) {
            throw new AuthenticationException();
        }
        return $next($request);
    }
}
