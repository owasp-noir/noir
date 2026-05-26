<?php

namespace app\controller;

use think\Controller;

class UserController extends Controller
{
    // Exposes: GET /user_controller/index (and fallback GET /user_controller)
    // Params: page (query), limit (query)
    public function index()
    {
        $page = input('page');
        $limit = input('limit');
    }

    // Exposes: GET /user_controller/view
    // Params: id (query), get_id (query)
    public function view($id)
    {
        $get_id = input('get.get_id');
    }

    // Exposes: GET+POST /user_controller/create
    // Params: username (form), password (form)
    public function create()
    {
        $username = request()->post('username');
        $password = request()->post('password');
    }
}
