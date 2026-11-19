<?php
use Illuminate\Support\Facades\Route;

Route::prefix('blog')->group(function () {
    Route::get('/', 'BlogController@index');
    Route::post('/posts', 'BlogController@store');
});
