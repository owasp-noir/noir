<?php

use Illuminate\Foundation\Application;
use Illuminate\Support\Facades\Route;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        health: '/up',
        then: function () {
            Route::middleware(['web', 'auth'])
                ->prefix('admin')
                ->group(base_path('routes/admin.php'));
        },
    )
    ->create();
