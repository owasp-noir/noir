<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Support\Facades\Log;
class AltRefuse
{
    public function handle($request, Closure $next)
    {
        if (! $request->user()):
            Log::info("guest");
            abort(401);
        endif;
        return $next($request);
    }
}
