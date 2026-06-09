<?php

namespace App\Http\Controllers;

class PhotoController extends Controller
{
    public function index()
    {
        $photos = PhotoRepository::latest();
        return response()->json($photos);
    }

    public function show($photo)
    {
        $record = PhotoRepository::find($photo);
        return response()->json($record);
    }
}
