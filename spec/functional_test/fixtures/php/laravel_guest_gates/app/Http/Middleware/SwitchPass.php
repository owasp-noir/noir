<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class SwitchPass
{
    public function handle($request, Closure $next)
    {
        switch ($request->route()->getName()) {
            case "public.show":
                if (! $request->user()) {
                    return $next($request);
                }
                break;
        }
        if (! $request->user()) {
            abort(401);
        }
        return $next($request);
    }
}
