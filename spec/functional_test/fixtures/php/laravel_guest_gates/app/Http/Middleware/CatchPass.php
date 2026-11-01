<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class CatchPass
{
    public function handle($request, Closure $next)
    {
        try {
            $this->verifySignature($request);
        } catch (\Exception $e) {
            if (! $request->user()) {
                return $next($request);
            }
        }
        if (! $request->user()) {
            abort(401);
        }
        return $next($request);
    }
}
