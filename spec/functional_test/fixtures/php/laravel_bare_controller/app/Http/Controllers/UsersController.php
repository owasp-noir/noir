<?php

namespace App\Http\Controllers;

class UsersController extends Controller
{
    public function __construct()
    {
        $this->middleware('auth');
    }

    public function index()
    {
        return 'users';
    }
}
