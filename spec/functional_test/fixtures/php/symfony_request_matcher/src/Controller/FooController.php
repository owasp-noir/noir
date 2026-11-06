<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\Routing\Attribute\Route;

class FooController extends AbstractController
{
    #[Route(path: '/foo', name: 'foo')]
    public function foo()
    {
        return $this->json([]);
    }
}
