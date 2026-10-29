<?php
use App\Http\Controllers\UserController;

Route::middleware(['auth:sanctum'])->group(function () {
    Route::middleware('can:administrator')->group(function () {
        Route::delete('settings/users/{user}', [UserController::class, 'destroy']);
    });
    Route::delete('users/{user}', [UserController::class, 'destroy'])->middleware('can:delete,user');
});
