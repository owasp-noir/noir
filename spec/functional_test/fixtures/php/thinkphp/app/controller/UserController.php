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

    // Test: Advanced request parameters: $this->request, Facades, getMore/postMore, superglobals
    // Exposes: GET+POST /user/advanced
    public function advanced()
    {
        // 1. $this->request->param
        $admin_token = $this->request->param('admin_token');

        // 2. Facades
        $query_facade = Request::get('query_facade');
        $x_header = \think\facade\Request::header('X-Facade-Header');

        // 3. getMore & postMore (CRMEB-style)
        $crmeb_get = $this->request->getMore([
            ['crmeb_page', 1],
            ['crmeb_limit', 10]
        ]);
        $crmeb_post = Util::postMore([
            ['crmeb_form_field', '']
        ]);

        // 4. Parameter existence checks
        $verbose = input('?verbose');

        // 5. Superglobals & Server variables
        $username_raw = $_POST['username_raw'];
        $correlation = $_SERVER['HTTP_X_CORRELATION_ID'];

        // 6. $request->only
        $only_fields = $this->request->only(['email', 'phone']);
    }
}
