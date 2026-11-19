<?php
namespace Acme\Billing\Http\Controllers;

use Illuminate\Http\Request;

class InvoiceController
{
    public function store(Request $request) { return $request->input('amount'); }
}
