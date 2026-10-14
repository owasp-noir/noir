<?php
namespace App\Controller;

use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

// Not under any imported directory: keeps its own path.
class StatusController
{
    #[Route('/status', name: 'status', methods: ['GET'])]
    public function status(): Response
    {
        return new Response();
    }
}
