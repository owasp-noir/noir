<?php

namespace App\Controller;

// Another package's Route attribute: not a Symfony route.
use Spiral\Router\Annotation\Route;

class SpiralController
{
    #[Route(route: '/spiral', name: 'spiral.list', methods: 'GET')]
    public function list()
    {
        return 1;
    }
}
