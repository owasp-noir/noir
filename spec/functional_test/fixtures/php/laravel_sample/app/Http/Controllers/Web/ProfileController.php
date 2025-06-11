<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

class ProfileController extends Controller
{
    public function show(string $userId)
    {
        // In a real app, you'd fetch the user by $userId
        return "Profile page for user: " . $userId;
    }

    public function contact(Request $request, string $userId)
    {
        $message = $request->input('message');
        $subject = $request->input('subject', 'Default Subject'); // With default
        // Process contact form
        return "Contact form submitted for user: " . $userId . " with message: " . $message;
    }
}
