<?php

use Illuminate\Support\Facades\Route;

Route::get('/users', ['uses' => 'UsersController@index']);
Route::get('/pages', 'PagesController@index');
