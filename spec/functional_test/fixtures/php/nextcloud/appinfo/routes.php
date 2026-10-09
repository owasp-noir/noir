<?php

return array_merge_recursive(
    include __DIR__ . '/routes/routesShareController.php',
    [
        'routes' => [
            ['name' => 'page#index', 'url' => '/', 'verb' => 'GET'],
            ['name' => 'note#update', 'url' => '/notes/{id}', 'verb' => 'PUT'],
            // ['name' => 'page#legacy', 'url' => '/legacy', 'verb' => 'GET'],
            // `root` is only honoured for Nextcloud's own root-URL apps.
            ['name' => 'page#index', 'url' => '/home', 'verb' => 'GET', 'root' => '/elsewhere'],
        ],
        'ocs' => [
            ['name' => 'api#share', 'url' => '/api/v1/share', 'verb' => 'POST'],
        ],
        'resources' => [
            'note' => ['url' => '/notes'],
        ],
    ]
);
