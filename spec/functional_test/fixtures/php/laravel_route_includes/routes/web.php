<?php
use Illuminate\Support\Facades\Route;

Route::get('/', fn () => 'home');
Route::middleware(['auth'])->prefix('admin')->group(function () {
    require __DIR__.'/admin.php';
});
require __DIR__.'/auth.php';
