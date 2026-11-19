<?php
use Illuminate\Support\Facades\Route;

Route::group(['middleware' => ['admin'], 'prefix' => 'admin'], function () {
    Route::get('dashboard', [\Webkul\Admin\Http\Controllers\DashboardController::class, 'index']);
});
