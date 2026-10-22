<?php

namespace app\test\controller;

use think\Controller;

// Multi-app mode: `app/test` is the `test` app of the exam feature.
class Index extends Controller
{
    public function index()
    {
        $id = input('id');
    }
}
