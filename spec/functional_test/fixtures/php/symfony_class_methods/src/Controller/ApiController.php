<?php
namespace App\Controller;

use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

// Symfony merges the class-level `methods` into every route's own.
#[Route('/v1', methods: ['POST'])]
class ApiController
{
    #[Route('/inherit')]
    public function inherit(): Response { return new Response(''); }

    #[Route('/own', methods: ['PUT'])]
    public function own(): Response { return new Response(''); }
}
