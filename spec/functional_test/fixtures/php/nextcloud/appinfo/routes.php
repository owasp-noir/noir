<?php

return [
    'routes' => [
        ['name' => 'page#index', 'url' => '/', 'verb' => 'GET'],
        ['name' => 'note#update', 'url' => '/notes/{id}', 'verb' => 'PUT'],
        // ['name' => 'page#legacy', 'url' => '/legacy', 'verb' => 'GET'],
    ],
    'ocs' => [
        ['name' => 'api#share', 'url' => '/api/v1/share', 'verb' => 'POST'],
    ],
    'resources' => [
        'note' => ['url' => '/notes'],
    ],
];
