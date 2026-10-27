<?php

namespace App\Http\Controllers;

class BracelessController extends Controller
{
    public function __construct()
    {
        if (config('app.private'))
            $this->middleware('auth');
    }

    public function index()
    {
        return 'list';
    }
}
