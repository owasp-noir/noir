<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
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

    public function index()
    {
        return response()->json(['users' => []]);
    }

    public function store(Request $request)
    {
        return response()->json(['message' => 'User created']);
    }

    public function show($id)
    {
        return response()->json(['user' => ['id' => $id]]);
    }

    public function update(Request $request, $id)
    {
        return response()->json(['message' => 'User updated', 'id' => $id]);
    }

    public function destroy($id)
    {
        return response()->json(['message' => 'User deleted', 'id' => $id]);
    }
}