<?php
namespace App\Http\Middleware {
    use Closure;
    class BracedNs
    {
        public function handle($request, Closure $next)
        {
            abort_unless($request->user(), 401);
            return $next($request);
        }
    }
}
