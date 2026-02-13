<?php
use Cake\Routing\Route\DashedRoute;
use Cake\Routing\RouteBuilder;

return static function (RouteBuilder $routes) {
    $routes->setRouteClass(DashedRoute::class);

    $routes->scope('/', function (RouteBuilder $builder) {
        $builder->connect('/', ['controller' => 'Pages', 'action' => 'display', 'home']);
        $builder->connect('/pages/*', ['controller' => 'Pages', 'action' => 'display']);

        $builder->get('/about', ['controller' => 'Pages', 'action' => 'about']);

        $builder->resources('Articles');

        $builder->scope('/admin', function (RouteBuilder $builder) {
            $builder->connect('/dashboard', ['controller' => 'Admin', 'action' => 'index']);
            $builder->get('/users', ['controller' => 'Users', 'action' => 'index']);
        });

        $builder->post('/login', ['controller' => 'Users', 'action' => 'login']);
    });
};
