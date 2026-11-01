<?php
use Cake\Routing\RouteBuilder;
use Cake\Routing\Route\DashedRoute;
return static function (RouteBuilder $routes) {
    $routes->scope('/', function (RouteBuilder $builder) {
        $builder->resources('Sizes', function (RouteBuilder $routes) {
            $routes->resources('Stocks', ['only' => ['index']]);
        });
        $builder->resources('Licenses', function (RouteBuilder $routes) {
            $routes->resources('Seats', ['only' => ['index']]);
        });
        $builder->resources('Caches', function (RouteBuilder $routes) {
            $routes->resources('Keys', ['only' => ['index']]);
        });
    });
};
