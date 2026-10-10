<?php

namespace App\Providers;

use Illuminate\Foundation\Support\Providers\RouteServiceProvider as ServiceProvider;
use Illuminate\Support\Facades\Route;

class RouteServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        $this->routes(function () {
            // Route::prefix('old')->group(base_path('routes/web.php'));
            Route::middleware('web')->group(function () {
                Route::middleware('auth')
                    ->prefix('/admin')
                    ->group(base_path('routes/admin.php'));
            });

            Route::group([
                'middleware' => 'api',
                'prefix' => 'api',
            ], function ($router) {
                require base_path('routes/api.php');
            });

            Route::middleware('web')->group(base_path('routes/web.php'));
        });
    }
}
