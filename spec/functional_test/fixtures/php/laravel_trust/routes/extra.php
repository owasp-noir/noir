<?php

use App\Http\Controllers\AccountController;
use App\Http\Controllers\CheckController;
use App\Http\Controllers\ItemController;
use App\Http\Controllers\StaffAccountController;
use Illuminate\Support\Facades\Route;

$middleware = ['auth:sanctum,api'];

Route::get('/vars/direct', [ItemController::class, 'file'])->middleware($middleware);
Route::prefix('vars')->group(function () use ($middleware) {
    Route::get('captured', [ItemController::class, 'file'])->middleware($middleware);
});
Route::prefix('vars')->group(function () {
    // Not captured: undefined inside the closure, so no middleware.
    Route::get('uncaptured', [ItemController::class, 'file'])->middleware($middleware);
});
Route::prefix('vars')->middleware($middleware)->group(function () {
    Route::get('grouped', [ItemController::class, 'file']);
});

Route::domain(config('app.domain'))->prefix(config('portfolio.path'))->group(function () {
    Route::get('cfg', [ItemController::class, 'file']);
});
Route::prefix(config('portfolio.nested.path'))->group(function () {
    Route::get('cfg', [ItemController::class, 'file']);
});
Route::prefix(config('portfolio.missing', 'fallback'))->group(function () {
    Route::get('cfg', [ItemController::class, 'file']);
});

Route::get('/acct/open', [AccountController::class, 'open']);
Route::post('/acct/close', [AccountController::class, 'close']);
Route::post('/acct/profile', [AccountController::class, 'saveProfile']);
Route::post('/staff/close', [StaffAccountController::class, 'close']);

Route::get('/check/mine', [CheckController::class, 'mine']);
Route::get('/check/own', [CheckController::class, 'own']);
Route::get('/check/late', [CheckController::class, 'late']);
Route::get('/check/role', [CheckController::class, 'role']);
Route::get('/check/inner/{id}', [CheckController::class, 'inner']);
Route::get('/check/after', [CheckController::class, 'after']);
Route::get('/check/validated', [CheckController::class, 'validated']);
