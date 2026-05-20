<?php

declare(strict_types=1);

use Hyperf\HttpServer\Router\Router;

Router::addRoute(['GET', 'POST'], '/items', [App\Controller\ItemController::class, 'index']);
Router::get('/items/{itemId}', [App\Controller\ItemController::class, 'show']);
Router::addGroup('/api/v1', function () {
    Router::get('/me', [App\Controller\AuthController::class, 'me']);
    Router::post('/login', [App\Controller\AuthController::class, 'login']);

    Router::addGroup('/admin', function () {
        Router::delete('/users/{id}', [App\Controller\AdminController::class, 'destroy']);
    });
});
