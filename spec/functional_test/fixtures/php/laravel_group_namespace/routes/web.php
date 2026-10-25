<?php

use Illuminate\Support\Facades\Route;

Route::group(
    ['middleware' => 'members', 'namespace' => 'App\Http\Controllers', 'prefix' => 'account'],
    static function (): void {
        Route::get('', 'AccountController@index');
        Route::post('password', ['uses' => 'AccountController@password', 'as' => 'account.password']);
        Route::get('open', ['uses' => 'AccountController@index'])->withoutMiddleware(['members']);
        Route::get('throttled', 'AccountController@index')->withoutMiddleware('throttle');
    }
);

Route::group(['namespace' => 'App\Http\Controllers'], static function (): void {
    Route::group(['namespace' => 'Admin'], static function (): void {
        Route::get('stats', ['as' => 'stats', 'uses' => 'StatsController@show']);
    });
});
