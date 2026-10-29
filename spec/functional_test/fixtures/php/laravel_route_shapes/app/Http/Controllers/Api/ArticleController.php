<?php

namespace App\Http\Controllers\Api;

use Illuminate\Http\Request;

class ArticleController extends Controller
{
    public function __construct()
    {
        $this->middleware('auth');
    }

    public function store(Request $request)
    {
        return $request->input('article.title');
    }
}
