<?php

namespace App\Http\Controllers;

class CtorController extends Controller
{
    protected $public = ['index'];

    public function __construct()
    {
        $this->middleware('auth', ['except' => ['index', 'show']]);
        $this->middleware('staff')->except($this->public);
    }

    public function index()
    {
        return 'list';
    }

    public function store()
    {
        return 'made';
    }
}
