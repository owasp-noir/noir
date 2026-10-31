<?php

use App\Http\Controllers\FrameworkController;
use App\Http\Controllers\ItemController;
use App\Http\Controllers\PlainController;
use Illuminate\Support\Facades\Route;

Route::post('/items', [ItemController::class, 'store']);
Route::post('/plain', [PlainController::class, 'store']);
Route::post('/framework', [FrameworkController::class, 'store']);
