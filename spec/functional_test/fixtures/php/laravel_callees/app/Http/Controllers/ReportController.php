<?php

namespace App\Http\Controllers;

class ReportController extends Controller
{
    public static function index()
    {
        $report = ReportBuilder::generate();
        return response()->json($report);
    }
}
