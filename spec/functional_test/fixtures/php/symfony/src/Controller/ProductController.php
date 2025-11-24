<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Attribute\Route;

class ProductController extends AbstractController
{
    #[Route('/api/products', methods: ['GET'])]
    public function index(): JsonResponse
    {
        return $this->json([]);
    }

    #[Route('/api/products/{slug}', methods: ['GET'])]
    public function show(string $slug): JsonResponse
    {
        return $this->json(['slug' => $slug]);
    }

    #[Route('/api/products', methods: ['POST'])]
    public function create(Request $request): JsonResponse
    {
        $name = $request->request->get('name');
        $price = $request->request->get('price');
        $category = $request->get('category');
        $userAgent = $request->headers->get('User-Agent');
        $image = $request->files->get('image');
        return $this->json(['status' => 'created']);
    }

    #[Route('/api/products/{slug}', methods: ['PATCH'])]
    public function update(string $slug, Request $request): JsonResponse
    {
        $jsonContent = $request->getContent();
        $token = $request->headers->get('X-CSRF-Token');
        $cookieData = $request->cookies->get('preferences');
        return $this->json(['slug' => $slug, 'status' => 'updated']);
    }
}