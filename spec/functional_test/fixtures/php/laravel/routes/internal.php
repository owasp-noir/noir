<?php

use App\Http\Controllers\InternalController;
use Illuminate\Support\Facades\Route;

// Not named web.php / api.php: route files are recognized anywhere under
// routes/. The group uses a `static function (): void` closure, whose prefix
// must still be applied to the nested routes.
Route::prefix('internal')->group(static function (): void {
    Route::get('status', [InternalController::class, 'status']);
    Route::post('sync', [InternalController::class, 'sync']);
});
