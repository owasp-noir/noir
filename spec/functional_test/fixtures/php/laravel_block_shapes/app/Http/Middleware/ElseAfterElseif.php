<?php
namespace App\Http\Middleware;

use Closure;

class ElseAfterElseif
{
    public function handle($request, Closure $next)
    {
        $user = $request->user();
        if ($request->is("admin/*")) {
            $x = 1;
        } elseif ($user) {
            $x = 2;
        } else {
            return $next($request);
        }
        abort(403);
    }
}
