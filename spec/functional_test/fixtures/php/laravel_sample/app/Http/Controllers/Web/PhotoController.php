<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Http\Requests\StorePhotoRequest;

class PhotoController extends Controller
{
    public function index() { return "Photos index"; }
    public function create() { return "Create photo form"; }
    public function store(StorePhotoRequest $request) { // Uses FormRequest
        $caption = $request->input('caption'); // Also direct input access
        return "Photo stored with caption: " . $request->validated()['title'] . " and direct caption: " . $caption;
    }
    public function show(string $photo) { return "Showing photo: " . $photo; }
    public function edit(string $photo) { return "Editing photo: " . $photo; }
    public function update(Request $request, string $photo) {
        $description = $request->input('description');
        return "Updating photo: " . $photo;
    }
    public function destroy(string $photo) { return "Deleting photo: " . $photo; }
}
