<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Annotation\Route;

class UserController extends AbstractController
{
    /**
     * @Route("/api/users", methods={"GET"})
     */
    public function list(Request $request): JsonResponse
    {
        $users = [];
        return $this->json($users);
    }

    /**
     * @Route("/api/users/{id}", methods={"GET"})
     */
    public function show(int $id): JsonResponse
    {
        return $this->json(['id' => $id]);
    }

    /**
     * @Route("/api/users", methods={"POST"})
     */
    public function create(Request $request): JsonResponse
    {
        return $this->json(['status' => 'created']);
    }

    /**
     * @Route("/api/users/{id}", methods={"PUT"})
     */
    public function update(int $id, Request $request): JsonResponse
    {
        return $this->json(['id' => $id, 'status' => 'updated']);
    }

    /**
     * @Route("/api/users/{id}", methods={"DELETE"})
     */
    public function delete(int $id): JsonResponse
    {
        return $this->json(['status' => 'deleted']);
    }
}