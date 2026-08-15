<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\UserController;
use App\Http\Controllers\ProductController;

/*
|--------------------------------------------------------------------------
| Web Routes
|--------------------------------------------------------------------------
|
| Here is where you can register web routes for your application. These
| routes are loaded by the RouteServiceProvider and all of them will
| be assigned to the "web" middleware group. Make something great!
|
*/

Route::get('/', function () {
    return view('welcome');
});

Route::get('/dashboard', [UserController::class, 'dashboard'])->name('dashboard');
Route::view('/terms', 'terms');
Route::redirect('/legacy-dashboard', '/dashboard');

Route::get('/users', [UserController::class, 'index']);
Route::post('/users', [UserController::class, 'store']);
Route::get('/users/{id}', [UserController::class, 'show']);
Route::put('/users/{id}', [UserController::class, 'update']);
Route::delete('/users/{id}', [UserController::class, 'destroy']);

// Route::resource('phantoms', ProductController::class)
Route::resource('products', ProductController::class);
Route::resource('photos', ProductController::class)
    ->only(['index', 'show'])
    ->parameters(['photos' => 'photo']);
Route::apiResource('admin/widgets', ProductController::class)
    ->except(['destroy'])
    ->parameters(['widgets' => 'widget']);

Route::group(['prefix' => 'admin'], function () {
    Route::get('/settings', function () {
        return view('admin.settings');
    });
    Route::post('/settings', function () {
        return redirect('/admin/settings');
    });
    Route::query('/logs', function () {
        return response()->json(['logs' => []]);
    });
});

Route::match(['get', 'post'], '/contact', function () {
    return view('contact');
});

Route::match(['get', 'query'], '/filter', function () {
    return view('contact');
});

Route::query('/search', [ProductController::class, 'index']);

Route::addRoute('QUERY', '/advanced-search', function () {
    return response()->json(['status' => 'ok']);
});

Route::query('/search-chained', function () {
    return response()->json(['status' => 'ok']);
})->middleware('auth');

Route::middleware('auth')->query('/secure-search', function () {
    return response()->json(['status' => 'ok']);
});

Route::any('/webhook', function () {
    return response()->json(['status' => 'ok']);
});

Route::middleware('auth:sanctum')->get('/me', [UserController::class, 'me']);

Route::middleware(['auth'])->prefix('api/v1')->group(function () {
    Route::get('/profile', [UserController::class, 'profile']);
    Route::post('/profile', [UserController::class, 'updateProfile']);
    Route::query('/query-items', function () {
        return response()->json(['items' => []]);
    });
    Route::apiResource('tokens', ProductController::class);

    Route::prefix('reports')->group(function () {
        Route::get('/daily', [ProductController::class, 'dailyReport']);
    });
});

Route::prefix('tenant/{tenant}')->middleware('auth')->get('/dashboard', [UserController::class, 'tenantDashboard']);
