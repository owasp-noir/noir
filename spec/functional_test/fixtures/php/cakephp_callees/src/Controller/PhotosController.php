<?php

namespace App\Controller;

class PhotosController extends AppController
{
    public function index()
    {
        $photos = PhotoService::list();
        return $this->jsonList($photos);
    }

    public function add()
    {
        $payload = PhotoPayload::fromRequest($this->request);
        return PhotoService::create($payload);
    }

    public function view($id)
    {
        $photo = PhotoService::find($id);
        return $this->jsonPhoto($photo);
    }

    public function edit($id)
    {
        $payload = PhotoPayload::fromRequest($this->request);
        return PhotoService::update($id, $payload);
    }

    public function delete($id)
    {
        PhotoService::delete($id);
        return $this->emptyResponse();
    }
}
