<?php

use Illuminate\Support\Facades\Route;
use Livewire\Volt\Volt;

Volt::route('/counter', 'counter');

Route::middleware('auth')->prefix('admin')->group(function () {
    Volt::route('/posts/{post}', 'posts.show');
});

// Volt::route('/commented', 'counter');
