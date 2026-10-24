<?php

use App\Http\Controllers\ItemController;
use App\Http\Middleware\TokenGate;
use Illuminate\Support\Facades\Route;

Route::put('items/{id}', [ItemController::class, 'update']);
Route::get('ping', fn () => 'pong')->withoutMiddleware(TokenGate::class);
