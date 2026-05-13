<?php

use Cake\Routing\RouteBuilder;

return static function (RouteBuilder $routes) {
    $routes->scope('/', function (RouteBuilder $builder) {
        $builder->connect('/', ['controller' => 'Pages', 'action' => 'home']);
        $builder->get('/articles/:id', ['controller' => 'Articles', 'action' => 'view']);
        $builder->post('/articles', ['controller' => 'Articles', 'action' => 'add']);
        $builder->resources('Photos');
        $builder->get('/legacy', 'Legacy::index');
        $builder->connect('/computed', ['controller' => $controller, 'action' => 'show']);
    });
};
