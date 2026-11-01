<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Support\Facades\Log;
class AltElsePass
{
    public function handle($request, Closure $next)
    {
        if ($request->user()):
            Log::info("u");
            Log::info("v");
        else:
            return $next($request);
        endif;
        abort(401);
    }
}
