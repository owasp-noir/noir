<?php
use Cake\Routing\Route\DashedRoute;
use Cake\Routing\RouteBuilder;
use Cake\Routing\Router;

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

        // connect() with a chained ->setMethods([...]) must record the
        // restricted verbs instead of defaulting to GET.
        $builder->connect('/logout', ['controller' => 'Users', 'action' => 'logout'])
            ->setMethods(['POST']);
        $builder->connect('/sessions/{id}', ['controller' => 'Sessions', 'action' => 'update'])
            ->setPass(['id'])
            ->setMethods(['PUT', 'DELETE']);
    });

    // prefix() opens a prefixed scope just like scope().
    $routes->prefix('/groups', function (RouteBuilder $builder) {
        $builder->connect('/{id}', ['controller' => 'Groups', 'action' => 'view'])
            ->setPass(['id'])
            ->setMethods(['GET']);
    });

    // prefix() with an explicit ['path' => ...] option mounts under that path,
    // not the dasherized prefix name (so this is /v1.0/status, not /v10/status).
    $routes->prefix('v10', ['path' => '/v1.0'], function (RouteBuilder $builder) {
        $builder->get('/status', ['controller' => 'Api', 'action' => 'status']);
    });

    // Static Router facade form used by older apps and plugin route files.
    Router::scope('/legacy', function (RouteBuilder $routes) {
        $routes->get('/ping', ['controller' => 'Legacy', 'action' => 'ping']);
    });
};
