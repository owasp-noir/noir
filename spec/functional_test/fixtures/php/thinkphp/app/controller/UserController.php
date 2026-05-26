<?php

namespace app\controller;

use think\Controller;
use think\Request;

class UserController extends Controller
{
    // Test: Return type hint & input suffix (/d) & Attribute Route
    // Exposes: GET /user/index (and fallback GET /user), GET /home
    // Params: page (query), limit (query)
    #[Route('home', 'GET')]
    public function index(): string
    {
        $page = input('page/d');
        $limit = input('limit');
        return "index";
    }

    // Test: signature input $id, input suffix (/s), mixed query/form params & DocBlock Route
    // Exposes: GET+POST /user/view, GET+POST /profile/:id
    // Params: id (query/path), get_id (query), name (form)
    /**
     * @Route("profile/:id", "GET|POST")
     */
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
