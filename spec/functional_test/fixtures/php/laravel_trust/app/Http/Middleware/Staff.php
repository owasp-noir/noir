<?php

namespace App\Http\Middleware;

use Closure;

class Staff
{
    public function handle($request, Closure $next)
    {
        if (! $request->user() || ! $request->user()->is_staff) {
            return redirect(config('app.url'));
        }

        return $next($request);
    }
}
