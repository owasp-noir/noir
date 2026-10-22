<?php
use Phalcon\Mvc\Router;
use Phalcon\Mvc\Router\Group as RouterGroup;

$router = new Router();

$router->addGet(
    '/products/edit/{id}',
    'Products::edit'
);

$router->addPost(
    '/products/save',
    'Products::save'
);

$router->add(
    '/products/update',
    'Products::update'
)->via(['POST', 'PUT']);

$router->add('/legacy/info', 'Info::show');

$blog = new RouterGroup([
    'module'     => 'blog',
    'controller' => 'index',
]);

$blog->setPrefix('/blog');

$blog->add('/save', ['action' => 'save']);
$blog->add('/edit/{id}', ['action' => 'edit']);

$router->mount($blog);
