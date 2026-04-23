<?php
use Slim\Factory\AppFactory;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

require __DIR__ . '/vendor/autoload.php';

$app = AppFactory::create();

$app->get('/', function (Request $request, Response $response) {
    $response->getBody()->write('Hello');
    return $response;
});

$app->get('/search', function (Request $request, Response $response) {
    $q = $request->getQueryParams()['q'];
    return $response;
});

$app->post('/users', function (Request $request, Response $response) {
    $data = $request->getParsedBody();
    $name = $request->getParsedBody()['name'];
    return $response;
});

$app->get('/users/{id}', function (Request $request, Response $response, array $args) {
    $id = $args['id'];
    $token = $request->getHeaderLine('X-Auth-Token');
    return $response;
});

$app->put('/users/{id}', function (Request $request, Response $response, array $args) {
    $id = $args['id'];
    return $response;
});

$app->delete('/users/{id}', function (Request $request, Response $response, array $args) {
    return $response;
});

$app->map(['GET', 'POST'], '/login', function (Request $request, Response $response) {
    $session = $request->getCookieParams()['session'];
    return $response;
});

$app->group('/api', function (\Slim\Routing\RouteCollectorProxy $group) {
    $group->get('/items', function (Request $request, Response $response) {
        return $response;
    });

    $group->post('/items', function (Request $request, Response $response) {
        $title = $request->getParsedBody()['title'];
        return $response;
    });

    $group->get('/items/{itemId}', function (Request $request, Response $response, array $args) {
        $itemId = $args['itemId'];
        return $response;
    });

    $group->group('/admin', function (\Slim\Routing\RouteCollectorProxy $admin) {
        $admin->get('/stats', function (Request $request, Response $response) {
            return $response;
        });
    });
});

$app->run();
