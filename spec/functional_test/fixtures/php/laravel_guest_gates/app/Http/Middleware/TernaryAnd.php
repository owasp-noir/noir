<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class TernaryAnd
{
    public function handle($request, Closure $next)
    {
        $ok = $request->user() && $request->user()->isAdmin();
        if (! $ok) {
            abort(403);
        }
        return $next($request);
    }
}
