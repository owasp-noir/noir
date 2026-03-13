<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;

class PostController extends Controller
{
    public function __construct()
    {
        $this->middleware('auth');
    }

    public function index()
    {
        return response()->json(Post::all());
    }

    public function store(Request $request)
    {
        $this->authorize('create', Post::class);
        return response()->json(Post::create($request->all()));
    }
}
