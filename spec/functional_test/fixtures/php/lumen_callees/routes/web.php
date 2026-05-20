<?php

$router->get('/health', function () {
    $status = HealthCheck::ready();
    return response()->json(['status' => $status]);
});

$router->post('/users', function () use ($request) {
    $payload = BuildUser::fromRequest($request);
    $user = UserService::create($payload);
    return response()->json($user, 201);
});

$router->addRoute(['GET', 'POST'], '/contact', function () {
    ContactNotifier::deliver();
    return view('contact');
});

$router->group(['prefix' => 'api/v1'], function () use ($router) {
    $router->get('/ready', function () {
        return ReadyProbe::check();
    });
});

$router->get('/reports', 'ReportController@index');
