<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Support\Facades\Log;
class AltNested
{
    public function handle($request, Closure $next)
    {
        if ($request->is("public/*")):
            $x = 1;
            if (! $request->user()) { return $next($request); }
        endif;
        abort_unless($request->user(), 401);
        return $next($request);
    }
}
