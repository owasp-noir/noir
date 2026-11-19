<?php
use App\Http\Controllers\PhotoController;
use Illuminate\Support\Facades\Route;

Route::resource('control', PhotoController::class)->only(['index']);
Route::middleware(['auth', 'verified'])->resource('photos', PhotoController::class)->only(['index', 'store']);
Route::prefix('admin')->middleware('auth')->apiResource('users', PhotoController::class)->only(['index', 'destroy']);
Route::middleware('auth')->singleton('profile', PhotoController::class);
Route::middleware(['throttle:60,1', \App\Http\Middleware\Audit::class])->resource('albums', PhotoController::class)->only(['index']);
Route::inertia('/about', 'About');
Route::livewire('/posts/create', 'pages::post.create');
Route::middleware('auth')->group(function () {
    Route::inertia('/settings', 'Settings/Index');
});
Route::prefix('team')->group(function () {
    Route::middleware('auth')->apiResource('members', PhotoController::class)->only(['index']);
});
