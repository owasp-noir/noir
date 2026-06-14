<?php

// Mautic registers routes per bundle in this array, grouped by main/public/api.
// The `api` group is mounted under `/api`; `main`/`public` sit at the root.
return [
    'routes' => [
        'main' => [
            'mautic_test_index' => [
                'path'       => '/test',
                'controller' => 'Mautic\TestBundle\Controller\TestController::indexAction',
            ],
            'mautic_test_action' => [
                'path'       => '/test/{objectId}',
                'controller' => 'Mautic\TestBundle\Controller\TestController::executeAction',
                'method'     => 'POST',
            ],
        ],
        'public' => [
            'mautic_test_public' => [
                'path'       => '/public/ping',
                'controller' => 'Mautic\TestBundle\Controller\PublicController::pingAction',
            ],
        ],
        'api' => [
            'mautic_test_api_list' => [
                'path'       => '/widgets/{dir}',
                'controller' => 'Mautic\TestBundle\Controller\Api\WidgetApiController::listEntitiesAction',
            ],
            'mautic_test_api_save' => [
                'path'       => '/widgets/new',
                'controller' => 'Mautic\TestBundle\Controller\Api\WidgetApiController::newEntityAction',
                'method'     => 'GET|POST',
            ],
        ],
    ],
];
