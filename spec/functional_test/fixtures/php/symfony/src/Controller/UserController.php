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
        $page = $request->query->get('page');
        $limit = $request->query->get('limit');
        $search = $request->get('search');
        $apiKey = $request->headers->get('X-API-Key');
        $sessionId = $request->cookies->get('session_id');
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
        $name = $request->request->get('name');
        $email = $request->request->get('email');
        $authToken = $request->headers->get('Authorization');
        $avatar = $request->files->get('avatar');
        return $this->json(['status' => 'created']);
    }

    /**
     * @Route("/api/users/{id}", methods={"PUT"})
     */
    public function update(int $id, Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);
        $contentType = $request->headers->get('Content-Type');
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