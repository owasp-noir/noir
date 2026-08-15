<?php
use Phalcon\Mvc\Controller;

class UsersController extends Controller
{
    public function indexAction()
    {
    }

    public function showAction($id)
    {
        $token = $this->request->getHeader('X-Auth-Token');
    }
}
