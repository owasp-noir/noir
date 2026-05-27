<?php

use think\facade\Route;

// Exposes: GET /shop/orders
Route::get('orders', 'Order/list');
