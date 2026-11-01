<?php
namespace App\Http\Middleware;

use Closure;

class ElseInLoop
{
    public function handle($request, Closure $next)
    {
        $user = $request->user();
        foreach ($this->except as $path) {
            if ($user) {
                $x = 1;
            } else {
                return $next($request);
            }
        }
        abort(403);
    }
}
