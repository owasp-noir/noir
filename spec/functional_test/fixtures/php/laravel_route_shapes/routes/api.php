<?php

Route::group(['namespace' => 'Api'], function () {
    Route::post('users/login', 'AuthController@login');
    Route::resource('articles', 'ArticleController', ['only' => ['store']]);
    Route::post('drafts', 'ArticleController@store');
});
