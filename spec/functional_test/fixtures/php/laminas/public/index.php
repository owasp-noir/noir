<?php

use Mezzio\Application;
use Psr\Http\Message\ServerRequestInterface;

/** @var Application $app */
$app->get('/api/users', App\Handler\ListUsersHandler::class);
$app->post('/api/users', App\Handler\CreateUserHandler::class);
$app->route('/api/reports/{reportId}', App\Handler\ReportHandler::class, ['GET', 'PATCH']);
$app->delete('/api/users/{id:\d+}', function (ServerRequestInterface $request) {
    $force = $request->getQueryParams()['force'];
    return $force;
});
