<?php

use App\Http\Controllers\ItemController;
use Illuminate\Support\Facades\Route;

Route::post('/login', [ItemController::class, 'login']);
Route::get('/files/{path}', [ItemController::class, 'file'])->where('path', '.*$');
Route::get('/items/{id}', function ($id) {
    return Item::query()->where('id', '.*')->first();
})->whereNumber('id');
