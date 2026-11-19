<?php
use Illuminate\Support\Facades\Route;

Route::middleware('auth:api')->get('/blog', function () { return []; });
