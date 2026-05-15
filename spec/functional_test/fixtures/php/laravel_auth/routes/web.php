<?php

use Illuminate\Support\Facades\Route;

Route::get('/public', function () {
    return response()->json(['message' => 'public']);
});

Route::get('/profile', function () {
    return response()->json(['id' => auth()->id()]);
})->middleware('auth');

Route::post('/posts', function () {
    return response()->json(['created' => true]);
})->middleware('auth');
