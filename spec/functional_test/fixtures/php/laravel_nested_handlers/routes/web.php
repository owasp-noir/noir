<?php

use Illuminate\Support\Facades\Route;

// A `Route::…` call inside a handler body runs when a request hits the outer
// route, not at boot, so nothing it registers is attack surface. Whether it
// leaked out used to depend on which scan shape found it first.

// Same scan on both sides — this was already suppressed.
Route::get('/same-scan', function () {
    Route::get('/phantom-same-scan', function () { return 'x'; });
});

// Outer found by the `any` scan, inner by the verb scan — leaked.
Route::any('/any-outer', function () {
    Route::get('/phantom-in-any', function () { return 'x'; });
});

// Outer found by the chained scan, inner by the verb scan — leaked, and
// without the enclosing `chain/` prefix.
Route::middleware('auth')->prefix('chain')->post('/chained-outer', function () {
    Route::get('/phantom-in-chain', function () { return 'x'; });
    Route::view('/phantom-static', 'v');
});

// The canonical Laravel nesting. These ARE registered at boot and DO inherit
// the group prefix — the fix must not touch them.
Route::prefix('admin')->group(function () {
    Route::get('/users', 'UserController@index');
    Route::post('/users', 'UserController@store');
});
