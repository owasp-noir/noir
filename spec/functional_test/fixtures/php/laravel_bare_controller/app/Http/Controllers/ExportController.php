<?php

namespace App\Http\Controllers;

class ExportController extends Controller
{
    public function __construct()
    {
        $this->middleware('auth');
    }

    public function index()
    {
        return 'export';
    }
}
