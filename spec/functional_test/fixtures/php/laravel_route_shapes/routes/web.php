<?php

use App\Http\Controllers\Api\ArticleController as C;

Route::post('/a/'.config('x.y'), [C::class, 'store']);
Route::post('/b/'.'x', [C::class, 'store']);
Route::post('/c/' . $prefix, [C::class, 'store']);
Route::post('/e/' . \trans('x') . '/f', [C::class, 'store']);
Route::post(
    '/d',
    [C::class, 'store']
);
Route::permanentRedirect('/.well-known/carddav', '/dav');
Route::redirect('/old', '/new');
Route::view('/welcome', 'welcome');
