<?php

use Slim\Factory\AppFactory;

require __DIR__ . '/vendor/autoload.php';

$app = AppFactory::create();
$apiPrefix = '/api';
$base = '/v1';

// Route patterns written with an interpolated prefix.
$app->get("{$apiPrefix}/users", function ($request, $response) {
    return $response;
});

$app->post("$base/login", function ($request, $response) {
    return $response;
});

$app->get('/ok', function ($request, $response) {
    return $response;
});

// Not routes: a collection put() and a config getter.
$messages->put("$key", $message);
$timezone = $conf->get('general.timezone', 'UTC');

$app->run();
