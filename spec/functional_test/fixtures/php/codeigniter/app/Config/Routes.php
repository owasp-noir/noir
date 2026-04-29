<?php

use CodeIgniter\Router\RouteCollection;

/**
 * @var RouteCollection $routes
 */
$routes->get('/', 'Home::index');
$routes->get('about', 'Pages::about');
$routes->post('login', 'Auth::login');
$routes->get('users/(:num)', 'UserController::show/$1');
$routes->put('users/(:num)', 'UserController::update/$1');
$routes->delete('users/(:num)', 'UserController::delete/$1');

$routes->match(['get', 'post'], 'contact', 'ContactController::handle');

$routes->add('webhook', 'WebhookController::any');

$routes->resource('photos');
$routes->presenter('articles');

$routes->group('admin', function ($routes) {
    $routes->get('dashboard', 'AdminController::dashboard');
    $routes->get('users', 'AdminController::users');
});

$routes->group('api', ['namespace' => 'App\Controllers\Api'], function ($routes) {
    $routes->get('status', 'StatusController::index');
    $routes->post('items', 'ItemController::create');
});

$routes->environment('development', function ($routes) {
    $routes->get('debug', 'Debug::index');
});
