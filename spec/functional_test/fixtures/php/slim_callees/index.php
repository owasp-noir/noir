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

$app->get('/users', function (Request $request, Response $response) {
    $page = $request->getQueryParams()['page'];
    $users = UserService::list($page);
    AuditLog::write('list');
    $response->getBody()->write(json_encode($users));
    return $response;
});

$app->post('/users', function (Request $request, Response $response) {
    $payload = BuildUser::fromArray($request->getParsedBody());
    $created = UserService::create($payload);
    return JsonResponder::created($response, $created);
});

$app->map(['GET', 'POST'], '/login', function (Request $request, Response $response) {
    $session = $request->getCookieParams()['session'];
    AuthService::login($session);
    return $response;
});

$app->group('/api', static function (\Slim\Routing\RouteCollectorProxy $group) use ($app): void {
    $group->get('/items/{itemId}', function (Request $request, Response $response, array $args) {
        $item = ItemService::find($args['itemId']);
        return JsonResponder::ok($response, $item);
    });
});

$app->run();
