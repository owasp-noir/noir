<?php
use App\Http\Controllers\PostController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::get('/control', function (Request $request) {
    return $request->input('control-in');
});
Route::get('/posts', [PostController::class, 'index']);
Route::post('/posts', [PostController::class, 'store']);
Route::post('/token', function (Request $request) {
    $a = $request->str('name');
    $b = $request->collect('tags');
    $c = $request->hasAny(['x1', 'x2']);
    $d = $request->whenHas('promo', fn ($v) => $v);
    $e = $request->bearerToken();
    $f = $request->hasHeader('X-Tenant');
    $g = $request->json('meta.id');
    return 1;
});
