<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Attribute\Route;

#[Route(path: '/api/admin')]
class AdminController extends AbstractController
{
    #[Route(path: '/stats', methods: ['GET'])]
    public function stats(): JsonResponse
    {
        return $this->json(['ok' => true]);
    }

    /**
     * @Route(path="/reports/{id}", methods={"POST"})
     */
    public function report(string $id): JsonResponse
    {
        return $this->json(['id' => $id]);
    }
}
