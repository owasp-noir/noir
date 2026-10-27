<?php

namespace App\Http\Controllers;

use App\Http\Controllers\Concerns\ManagesProfile;
use Illuminate\Http\Request;

class AccountController extends Controller
{
    use ManagesProfile;

    const ENTITY_KEY = '_pe';

    public function __construct()
    {
        $this->middleware('staff')->except(['open']);
        $this->middleware('guest')->only(['open']);
        $this->middleware(function ($request, $next) {
            abort(403);
        });
        if (config('app.locked')) {
            $this->middleware('auth');
        }
    }

    public function open(Request $request)
    {
        return $request->has(self::ENTITY_KEY);
    }

    public function close(Request $request)
    {
        return $request->input('reason');
    }
}
