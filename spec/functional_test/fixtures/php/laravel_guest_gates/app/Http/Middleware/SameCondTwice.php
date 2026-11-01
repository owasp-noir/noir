<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class SameCondTwice
{
    public function handle($request, Closure $next)
    {
        if ($request->is("x")) {
            $y = 1;
        } elseif (! $request->user()) {
            $z = 2;
        }
        if (! $request->user()) {
            return $next($request);
        }
        abort(403, "two factor");
    }
}
