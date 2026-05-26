<?php

namespace app\controller;

use think\Controller;
use think\Request;

class UserController extends Controller
{
    // Test: Return type hint & input suffix (/d)
    // Exposes: GET /user/index (and fallback GET /user)
    // Params: page (query), limit (query)
    public function index(): string
    {
        $page = input('page/d');
        $limit = input('limit');
        return "index";
    }

    // Test: signature input $id, input suffix (/s), mixed query (get.get_id/s) and form (post.name/a) parameters
    // Exposes: GET+POST /user/view
    // Params: id (query), get_id (query), name (form)
    public function view($id)
    {
        $get_id = input('get.get_id/s');
        $name = input('post.name/a');
    }

    // Test: Request object type-hint in signature
    // Exposes: GET+POST /user/create
    // Params: username (form), password (form)
    // (Should NOT extract a query parameter named 'request'!)
    public function create(Request $request)
    {
        $username = $request->post('username');
        $password = $request->post('password');
    }
}
