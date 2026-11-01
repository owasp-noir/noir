<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class CommentNext
{
    public function handle($request, Closure $next)
    {
        $user = $request->user();
        if (! $user) {
            // never call $next($request) for guests
            report(new \Exception("guest"));
        }
        if (! $user) {
            abort(403);
        }
        return $next($request);
    }
}
