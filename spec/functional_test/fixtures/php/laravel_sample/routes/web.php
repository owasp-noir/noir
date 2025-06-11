<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Web\PageController;
use App\Http\Controllers\Web\ProfileController;
use App\Http\Controllers\Web\PhotoController;

Route::get('/', [PageController::class, 'home'])->name('home');
Route::get('/about', [PageController::class, 'about']);
Route::get('/users/{userId}', [ProfileController::class, 'show']);
Route::post('/users/{userId}/contact', [ProfileController::class, 'contact']);

Route::resource('photos', PhotoController::class);
