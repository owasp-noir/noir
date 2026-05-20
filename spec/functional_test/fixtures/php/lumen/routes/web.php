<?php

$router->get('/', function () use ($router) {
    return $router->app->version();
});

$router->get('/users', 'UserController@index');

$router->post('/users', function () {
    $name = $request->input('name');
    return response()->json(['name' => $name]);
});

$router->get('/users/{id}', function ($id) {
    $token = $request->header('X-Auth-Token');
    return response()->json(['id' => $id, 'token' => $token]);
});

$router->put('/users/{id}', 'UserController@update');

$router->delete('/users/{id}', 'UserController@destroy');

$router->group(['prefix' => 'api/v1', 'middleware' => 'auth'], function () use ($router) {
    $router->get('/me', function () {
        $session = $request->cookie('session');
        return response()->json(['session' => $session]);
    });

    $router->post('/items', function () {
        $title = $request->input('title');
        return response()->json(['title' => $title]);
    });

    $router->group(['prefix' => 'admin'], function () use ($router) {
        $router->get('/stats', 'AdminController@stats');

        $router->addRoute(['PUT', 'PATCH'], '/settings', function () {
            $value = $request->input('value');
            return response()->json(['value' => $value]);
        });
    });
});

$router->addRoute(['GET', 'POST'], '/login', function () {
    $email = $request->input('email');
    return response()->json(['email' => $email]);
});
