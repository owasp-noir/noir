<?php

use Mezzio\Application;
use Mezzio\Router\Route;
use Psr\Http\Message\ServerRequestInterface;

/** @var Application $app */
// $app->get('/docs/commented', App\Handler\CommentedHandler::class);
/*
 * $app->post('/docs/commented-block', App\Handler\CommentedBlockHandler::class);
 * $app->route('/docs/commented-any', App\Handler\CommentedAnyHandler::class);
 */
$app->get('/api/users', App\Handler\ListUsersHandler::class);
$app->post('/api/users', App\Handler\CreateUserHandler::class);
$app->route('/api/reports/{reportId}', App\Handler\ReportHandler::class, ['GET', 'PATCH']);
$app->route('/api/audit/{auditId}', App\Handler\AuditHandler::class);
$app->route('/api/broadcast', App\Handler\BroadcastHandler::class, Route::HTTP_METHOD_ANY);
$app->delete('/api/users/{id:\d+}', function (ServerRequestInterface $request) {
    $force = $request->getQueryParams()['force'];
    return $force;
});
