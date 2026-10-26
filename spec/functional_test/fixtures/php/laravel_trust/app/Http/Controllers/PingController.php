<?php

namespace App\Http\Controllers;

class PingController extends Controller
{
    public function __invoke()
    {
        return 'pong';
    }
}
