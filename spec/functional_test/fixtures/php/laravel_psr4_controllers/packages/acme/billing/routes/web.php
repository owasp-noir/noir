<?php
use Acme\Billing\Http\Controllers\InvoiceController;
use Illuminate\Support\Facades\Route;

Route::post('/billing/invoices', [InvoiceController::class, 'store']);
