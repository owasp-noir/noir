<?php

namespace App\Controller\Api;

use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Annotation\Route;

class ItemController extends BaseController
{
    #[Route(path: '/public/items/{id}', methods: ['PUT'])]
    public function update(Request $request, $id)
    {
        $this->requireUser();

        return $this->forward('App\Controller\NoteController::save', ['id' => $id]);
    }

    #[Route(path: '/public/ping', methods: ['GET'])]
    #[Security(name: 'Bearer')]
    public function ping()
    {
        return $this->json(['ok' => true]);
    }

    #[Route(path: '/_profiler/info', methods: ['GET'])]
    public function profilerInfo()
    {
        return $this->json([]);
    }
}
