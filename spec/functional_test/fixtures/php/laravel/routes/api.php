<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\UserController as ApiUserController;
use App\Http\Controllers\Api\PostController;

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
|
| Here is where you can register API routes for your application. These
| routes are loaded by the RouteServiceProvider and all of them will
| be assigned to the "api" middleware group. Make something great!
|
*/

Route::middleware('auth:sanctum')->get('/user', function (Request $request) {
    return $request->user();
});

Route::get('/health', function () {
    return response()->json(['status' => 'healthy']);
});

Route::apiResource('users', ApiUserController::class);
Route::apiResource('posts', PostController::class);

Route::group(['prefix' => 'v1'], function () {
    Route::get('/info', function () {
        return response()->json(['version' => '1.0']);
    });
    Route::post('/data', function () {
        return response()->json(['message' => 'Data received']);
    });
});

Route::get('/categories', [PostController::class, 'categories']);
Route::post('/categories', [PostController::class, 'createCategory']);
Route::get('/categories/{slug}', [PostController::class, 'showCategory']);

Route::patch('/status/{id}', function ($id) {
    return response()->json(['id' => $id, 'status' => 'updated']);
});

Route::options('/cors-test', function () {
    return response()->json(['cors' => 'enabled']);
});