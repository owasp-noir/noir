<?php

namespace Drupal\demo\Controller;

use Drupal\Core\Controller\ControllerBase;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Attribute\Route;

#[Route(path: '/demo-prefix', requirements: ['_permission' => 'x'])]
class DemoController extends ControllerBase {

  #[Route(
    path: '/demo/login',
    name: 'demo.login.http',
    methods: ['POST'],
    requirements: [
      '_user_is_logged_in' => 'FALSE',
      '_format' => 'json',
    ],
  )]
  public function login(Request $request) {
    return [];
  }

  #[Route(
    path: '/demo/reset/{uid}',
    name: 'demo.reset',
    requirements: [
      '_access' => 'TRUE',
    ],
  )]
  public function reset($uid) {
    return [];
  }

  #[Route(
    path: '/demo/{node}/edit',
    name: 'demo.edit',
    requirements: [
      '_entity_access' => 'node.update',
    ],
  )]
  public function edit($node) {
    return [];
  }

}
