<?php
namespace App\Controller\Admin;

use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

// Imported under /admin; the later `site` import excludes this directory, so
// it does not replace the /admin route.
class PanelController
{
    #[Route('/panel', name: 'admin_panel', methods: ['GET'])]
    public function panel(): Response
    {
        return new Response();
    }
}
