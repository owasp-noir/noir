<?php
namespace App\Controller;

use ApiPlatform\Metadata\Get;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

class PlainController
{
    #[Route('/control', methods: ['GET'])]
    public function control(): Response { return new Response(''); }

    // API Platform's `Get` declares an operation, not a controller route.
    #[Get('/api-platform-get')]
    public function apiPlatform(): Response { return new Response(''); }
}
