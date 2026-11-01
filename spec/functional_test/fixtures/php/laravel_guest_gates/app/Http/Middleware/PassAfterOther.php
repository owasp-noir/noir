<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class PassAfterOther
{
    public function handle($request, Closure $next)
    {
        if (! $request->user() && $request->is("login")) {
            return $next($request);
        }
        if (! $request->user()) {
            abort(401);
        }
        return $next($request);
    }
}
