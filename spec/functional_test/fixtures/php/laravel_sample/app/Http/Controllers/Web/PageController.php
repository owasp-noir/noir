<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller; // Assuming a base Controller exists or is not strictly needed for parsing

class PageController extends Controller
{
    public function home()
    {
        return 'Welcome Home!';
    }

    public function about()
    {
        return 'About Us Page';
    }
}
