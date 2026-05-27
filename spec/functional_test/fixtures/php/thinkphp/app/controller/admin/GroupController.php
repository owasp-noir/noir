<?php

namespace app\controller\admin;

use think\Controller;

class GroupController extends Controller
{
    // Exposes: GET /admin/group/index & GET /admin.group/index (and fallback /admin/group & /admin.group)
    public function index()
    {
        $id = input('id');
    }
}
