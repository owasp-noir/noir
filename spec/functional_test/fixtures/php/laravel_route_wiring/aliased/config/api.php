<?php

return [
    'prefix' => env('API_PREFIX', 'v1'),
    'middleware' => explode(',', env('API_MIDDLEWARE', 'api')),
];
