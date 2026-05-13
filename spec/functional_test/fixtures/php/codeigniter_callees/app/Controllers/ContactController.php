<?php

namespace App\Controllers;

class ContactController extends BaseController
{
    public function handle()
    {
        ContactNotifier::deliver();
        return view('contact');
    }
}
