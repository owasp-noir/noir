<?php

use CodeIgniter\Router\RouteCollection;

/**
 * @var RouteCollection $routes
 */
$routes->get('/', 'Home::index');
$routes->get('array-home', [Home::class, 'arrayIndex']);
$routes->get('users/(:num)', 'UserController::show/$1');
$routes->match(['get', 'post'], 'contact', 'ContactController::handle');
$routes->add('webhook', 'WebhookController::any');
$routes->resource('photos');

$routes->group('api', ['namespace' => 'App\Controllers\Api'], function ($routes) {
    $routes->get('status', 'StatusController::index');
});
