<?php
namespace App\Http\Middleware;

use Closure;

class ElseTopPass
{
    public function handle($request, Closure $next)
    {
        $user = $request->user();
        if ($user) {
            $user->touch();
        } else {
            return $next($request);
        }
        abort(403);
    }
}
