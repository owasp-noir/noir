<?php

namespace App\Controllers;

class Home extends BaseController
{
    public function index()
    {
        $payload = WelcomeService::build();
        return view('welcome_message', $payload);
    }

    public function arrayIndex()
    {
        $payload = ArrayHomeService::build();
        return view('array_home', $payload);
    }
}
