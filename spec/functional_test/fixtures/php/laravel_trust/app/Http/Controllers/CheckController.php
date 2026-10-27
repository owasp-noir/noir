<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class CheckController extends Controller
{
    public function mine(Request $request)
    {
        abort_unless($request->user(), 404);

        return Item::query()->simplePaginate();
    }

    public function own(Request $request)
    {
        $user = Auth::user();
        if (! $user) {
            return redirect('/login');
        }

        return $user;
    }

    public function late(Request $request)
    {
        if ($request->has('preview')) {
            return 'public';
        }
        abort_if(! $request->user(), 403);
    }

    public function validated(Request $request)
    {
        $request->validate(['q' => 'required']);
        if (! $request->user()) {
            return response('', 403);
        }
    }

    public function branch(Request $request)
    {
        if (! Auth::check()) {
            if ($request->has('preview')) {
                return view('preview');
            }
            abort(403);
        }
    }

    public function guarded(Request $request)
    {
        if (! Auth::check()) {
            try {
                $x = cache('public');
            } catch (\Exception $e) {
                throw $e;
            }

            return view('public', ['x' => $x]);
        }
    }

    public function after(Request $request)
    {
        Item::query()->update(['seen' => true]);
        if (! auth()->check()) {
            return redirect('/login');
        }
    }

    public function role(Request $request)
    {
        abort_if(! $request->user()->is_admin, 403);
    }

    public function inner(Request $request, $id)
    {
        if ($id) {
            abort_if(! $request->user(), 403);
        }
        return Item::query()->paginate(10, ['*'], 'page', $id);
    }
}
