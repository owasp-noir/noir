<?php

use think\facade\Route;

// 1. Basic explicit GET with param
Route::get('hello/:name', 'index/hello');

// 2. Basic explicit POST
Route::post('save', 'index/save');

// 3. Rule matching PUT|PATCH
Route::rule('update', 'index/update', 'PUT|PATCH');

// 4. Resource route (generates 7 endpoints)
Route::resource('blog', 'Blog');

// 5. Nested group prefix
Route::group('admin', function () {
    Route::get('dashboard', 'admin/Index/dashboard');
    Route::post('users', 'admin/User/save');
});

// 6. Route::any
Route::any('any-route', 'index/anyRoute');

// 7. Route::rule with '*' (any method)
Route::rule('rule-route', 'index/ruleRoute', '*');
