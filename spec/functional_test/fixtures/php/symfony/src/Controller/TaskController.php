<?php

namespace App\Controller;

use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Attribute\Route;

// `#[Route('')]` on an action routes the class prefix itself.
#[Route('/tasks', name: 'tasks_')]
class TaskController
{
    #[Route('', name: 'list', methods: ['GET'])]
    public function list(): JsonResponse
    {
        return new JsonResponse([]);
    }

    #[Route(path: '', name: 'create', methods: ['POST'])]
    public function create(): JsonResponse
    {
        return new JsonResponse([], 201);
    }
}
