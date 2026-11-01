<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Auth\AuthenticationException;
class UserVarThenAbort
{
    public function handle($request, Closure $next)
    {
        $user = $request->user();
        if ($user && $user->banned) {
            return response()->json(["e" => 1], 403);
        }
        abort_if(! $user, 401);
        return $next($request);
    }
}
