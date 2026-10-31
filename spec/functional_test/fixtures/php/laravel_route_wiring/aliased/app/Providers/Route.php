<?php

namespace App\Providers;

use Illuminate\Foundation\Support\Providers\RouteServiceProvider as Provider;
use Illuminate\Support\Facades\Route as Facade;

// Not named `*RouteServiceProvider`, and the facade is aliased.
class Route extends Provider
{
    public function map()
    {
        Facade::prefix('{tenant_id}')
            ->middleware('admin')
            ->namespace($this->namespace)
            ->group(base_path('routes/tenant.php'));

        Facade::prefix(config('api.prefix'))
            ->middleware(config('api.middleware'))
            ->group(base_path('routes/api.php'));
    }
}
