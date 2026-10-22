<?php
namespace App\Controller\Web;

use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

// Mounted under /{_locale} by config/routes.yaml.
class HomeController
{
    #[Route('/', name: 'home', methods: ['GET'])]
    public function index(): Response
    {
        return new Response();
    }
}
