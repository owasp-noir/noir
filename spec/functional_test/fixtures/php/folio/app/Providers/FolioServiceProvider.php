<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Laravel\Folio\Folio;

class FolioServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        Folio::path(resource_path('views/pages'))->middleware([
            'admin/*' => ['auth', 'can:admin'],
        ]);

        Folio::path(resource_path('views/docs'))->uri('/docs')->middleware([
            '*' => 'throttle:docs',
        ]);

        Folio::domain('{account}.example.com')->path(resource_path('views/tenant'))->uri('/tenant');

        // Folio::path(resource_path('views/old'));
    }
}
