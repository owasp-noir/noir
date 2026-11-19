<?php
use Cake\Routing\Route\DashedRoute;
use Cake\Routing\RouteBuilder;

return function (RouteBuilder $routes): void {
    $routes->setRouteClass(DashedRoute::class);

    $routes->scope('/', function (RouteBuilder $builder): void {
        $builder->connect('/', ['controller' => 'Pages', 'action' => 'display', 'home']);
        $builder->connect('/pages/*', 'Pages::display');
        $builder->fallbacks();
    });

    $routes->prefix('Admin', function (RouteBuilder $builder): void {
        $builder->fallbacks(DashedRoute::class);
    });

    // Plugin controllers live in the plugin: not enumerated.
    $routes->plugin('Blog', function (RouteBuilder $builder): void {
        $builder->fallbacks();
    });
};
