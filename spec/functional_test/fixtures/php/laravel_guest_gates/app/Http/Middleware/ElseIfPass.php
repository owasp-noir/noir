<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class ElseIfPass
{
    public function handle($request, Closure $next)
    {
        if ($request->is("admin/*")) {
            $x = 1;
        } elseif (! $request->user()) {
            return $next($request);
        }
        if (! $request->user()) {
            abort(401);
        }
        return $next($request);
    }
}
