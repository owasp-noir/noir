<?php

use Laminas\Router\Http\Hostname;
use Laminas\Router\Http\Literal;
use Laminas\Router\Http\Method;
use Laminas\Router\Http\Segment;

return [
    'router' => [
        'routes' => [
            'home' => [
                'type' => Literal::class,
                'options' => [
                    'route' => '/',
                    'defaults' => [
                        'controller' => App\Controller\HomeController::class,
                        'action' => 'index',
                    ],
                ],
            ],
            'user' => [
                'type' => Segment::class,
                'options' => [
                    'route' => '/users[/:id]',
                    'constraints' => [
                        'id' => '[0-9]+',
                    ],
                    'defaults' => [
                        'controller' => App\Controller\UserController::class,
                        'action' => 'show',
                    ],
                ],
            ],
            'api' => [
                'type' => Segment::class,
                'options' => [
                    'route' => '/api',
                ],
                'may_terminate' => false,
                'child_routes' => [
                    'items' => [
                        'type' => Segment::class,
                        'options' => [
                            'route' => '/items',
                        ],
                    ],
                    'item' => [
                        'type' => Segment::class,
                        'options' => [
                            'route' => '/items/:itemId',
                            'constraints' => [
                                'itemId' => '[0-9]+',
                            ],
                        ],
                    ],
                ],
            ],
            'admin' => [
                'type' => Segment::class,
                'options' => [
                    'route' => '/admin',
                ],
                'may_terminate' => false,
                'child_routes' => [
                    'post_only' => [
                        'type' => Method::class,
                        'options' => [
                            'verb' => 'POST',
                        ],
                        'may_terminate' => false,
                        'child_routes' => [
                            'users' => [
                                'type' => Literal::class,
                                'options' => [
                                    'route' => '/users',
                                ],
                            ],
                        ],
                    ],
                ],
            ],
            'api_host' => [
                'type' => Hostname::class,
                'options' => [
                    'route' => 'api.example.test',
                ],
                'may_terminate' => false,
                'child_routes' => [
                    'status' => [
                        'type' => Literal::class,
                        'options' => [
                            'route' => '/status',
                        ],
                    ],
                ],
            ],
        ],
    ],
];
