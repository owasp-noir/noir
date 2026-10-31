<?php

namespace App\Http\Middleware;

use Closure;

// Sends everyone to the login page once installed: no auth guard.
class InstalledRedirect
{
    public function handle($request, Closure $next)
    {
        if (config('app.installed', false) == false) {
            return $next($request);
        }

        return redirect()->route('login');
    }
}
