<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\Routing\Attribute\Route;

class LogController extends AbstractController
{
    #[Route(path: '/logs', name: 'logs')]
    public function show()
    {
        $this->denyAccessUnlessGranted('@system.show_logs');

        return $this->json([]);
    }

    #[Route(path: '/api/info', name: 'info')]
    public function info()
    {
        return $this->json([]);
    }

    #[Route(path: '/maybe/info', name: 'maybe')]
    public function maybe()
    {
        return $this->json([]);
    }

    #[Route(path: '/open/info', name: 'open')]
    public function open()
    {
        return $this->json([]);
    }
}
