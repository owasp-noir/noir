<?php
namespace App\Http\Middleware;
use Closure;
if (! class_exists(IfClassExists::class)) {
    class IfClassExists
    {
        public function handle($request, Closure $next)
        {
            abort_unless($request->user(), 401);
            return $next($request);
        }
    }
}
