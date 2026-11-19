<?php
use Illuminate\Support\Facades\Route;
Route::get('/users', fn () => []);
Route::prefix('beta')->group(__DIR__.'/v1/beta.php');
