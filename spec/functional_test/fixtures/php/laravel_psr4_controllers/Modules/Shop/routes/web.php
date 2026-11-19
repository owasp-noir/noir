<?php
use Illuminate\Support\Facades\Route;
use Modules\Shop\Http\Controllers\ShopController;

Route::get('/shop', [ShopController::class, 'index']);
Route::post('/shop/orders', [ShopController::class, 'store']);
