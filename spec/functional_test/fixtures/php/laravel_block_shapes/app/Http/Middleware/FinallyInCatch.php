<?php
namespace App\Http\Middleware;

use Closure;

class FinallyInCatch
{
    public function handle($request, Closure $next)
    {
        try {
            $x = 1;
        } catch (\Exception $e) {
            try {
                report($e);
            } finally {
                if (! $request->user()) {
                    return $next($request);
                }
            }
        }
        abort(403);
    }
}
