<?php

$params = require __DIR__ . '/params.php';

$config = [
    'id' => 'basic',
    'basePath' => dirname(__DIR__),
    'bootstrap' => ['log'],
    'components' => [
        'request' => [
            'cookieValidationKey' => 'secret',
        ],
        'urlManager' => [
            'enablePrettyUrl' => true,
            'showScriptName' => false,
            'rules' => [
                'GET /posts' => 'post/index',
                'POST /posts' => 'post/create',
                'GET /posts/<id:\d+>' => 'post/view',
                'PUT /posts/<id:\d+>' => 'post/update',
                'DELETE /posts/<id:\d+>' => 'post/delete',
                '/articles/<slug:[\w-]+>' => 'article/view',
                'GET /health' => 'site/health',
            ],
        ],
    ],
    'params' => $params,
];

return $config;
