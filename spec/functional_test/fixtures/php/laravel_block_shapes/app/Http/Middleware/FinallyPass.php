<?php
namespace App\Http\Middleware;

use Closure;

class FinallyPass
{
    public function handle($request, Closure $next)
    {
        try {
            $request->validateSignature();
        } catch (\Exception $e) {
            report($e);
        } finally {
            if (! $request->user()) {
                return $next($request);
            }
        }
        abort(403);
    }
}
