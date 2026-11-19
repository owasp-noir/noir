<?php
namespace App\Http\Controllers;

use Illuminate\Support\Facades\Request as RequestFacade;

class PostController extends Controller
{
    public function index()
    {
        $posts = Post::latest()->filter(request(['search', 'category']))->get();
        $sort = request('sort', 'asc');
        $page = request()->page_size;
        $tag = RequestFacade::input('tag');
        return view('posts.index');
    }

    public function store()
    {
        $attributes = request()->validate(['title' => 'required', 'body' => 'required']);
        $slug = request('slug');
        return redirect('/');
    }
}
