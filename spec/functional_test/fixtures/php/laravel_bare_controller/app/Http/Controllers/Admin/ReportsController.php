<?php

namespace App\Http\Controllers\Admin;

class ReportsController extends Controller
{
    public function __construct()
    {
        $this->middleware('auth');
    }

    public function index()
    {
        return 'admin reports';
    }
}
