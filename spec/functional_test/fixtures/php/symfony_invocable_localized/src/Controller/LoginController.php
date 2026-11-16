<?php

namespace App\Controller;

use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\Security\Http\Attribute\IsGranted;

#[Route('/api/login', name: 'api_login', methods: ['POST'])]
final class LoginController
{
    public function __construct(private readonly TokenIssuer $tokens)
    {
    }

    public function __invoke(Request $request): JsonResponse
    {
        $user = $request->request->get('username');

        return new JsonResponse(['token' => $this->tokens->issue($user)]);
    }
}

#[Route('/api/logout', methods: ['POST'])]
#[IsGranted('ROLE_USER')]
final class LogoutController
{
    public function __invoke(): JsonResponse
    {
        return new JsonResponse(null, 204);
    }
}
