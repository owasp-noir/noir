<?php

return [
    'domain' => env('PORTFOLIO_DOMAIN', config('app.domain')),
    'path' => env('PORTFOLIO_PATH', '/i/portfolio'),
    'nested' => [
        'path' => 'deep',
    ],
];
