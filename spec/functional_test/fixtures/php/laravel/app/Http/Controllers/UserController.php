<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Http\Requests\UpdateUserRequest;
use Illuminate\Http\Response;
use Illuminate\Foundation\Auth\Access\AuthorizesRequests;
use Illuminate\Foundation\Validation\ValidatesRequests;
use Illuminate\Routing\Controller as BaseController;

class UserController extends BaseController
{
    use AuthorizesRequests, ValidatesRequests;

    public function dashboard()
    {
        return view('dashboard');
    }

    public function index(Request $request)
    {
        $search = $request->input('search');
        $sort = $request->query('sort');
        $page = request()->get('page');
        $locale = $request->header('Accept-Language');
        $theme = $request->cookie('theme');
        return response()->json(['users' => []]);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => 'required|max:255',
            'email' => ['required', 'email'],
            'address.city' => 'nullable',
        ], [
            'required' => 'The :attribute field is required.',
        ]);
        $avatar = $request->file('avatar');
        return response()->json(['message' => 'User created']);
    }

    public function show($id)
    {
        return response()->json(['user' => ['id' => $id]]);
    }

    public function update(UpdateUserRequest $request, $id)
    {
        return response()->json(['message' => 'User updated', 'id' => $id]);
    }

    public function destroy($id)
    {
        return response()->json(['message' => 'User deleted', 'id' => $id]);
    }
}