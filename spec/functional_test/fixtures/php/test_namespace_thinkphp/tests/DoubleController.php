<?php

namespace tests;

use think\Controller;

class DoubleController extends Controller
{
    public function index()
    {
        $double = input('double');
    }
}
