<?php

use Slim\Factory\AppFactory;
use Slim\Routing\RouteCollectorProxy;

require __DIR__ . '/vendor/autoload.php';

$app = AppFactory::create();

// CORS preflight catch-all from the Slim docs.
$app->options('/{routes:.+}', function ($request, $response) {
    return $response;
});

$app->get('/news[/{year:[0-9]{4}}[/{month:[0-9]{2}}]]', function ($request, $response, array $args) {
    return $response;
});

$app->get('/users/{id:[0-9]+}', function ($request, $response, array $args) {
    return $response;
});

$app->get('/users/{name}', function ($request, $response, array $args) {
    return $response;
});

$app->group('/books', function (RouteCollectorProxy $group) {
    $group->map(['GET', 'DELETE'], '[/{id:\d+}]', function ($request, $response, array $args) {
        return $response;
    });
});

$app->run();
