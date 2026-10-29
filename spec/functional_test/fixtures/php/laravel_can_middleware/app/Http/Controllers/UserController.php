<?php
namespace App\Http\Controllers;

class UserController extends Controller
{
    public function destroy($user) { $user->delete(); return 1; }
}
