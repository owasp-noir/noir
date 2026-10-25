<?php
namespace App\Controller\Web\Auth;

use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

// Loaded by the `web` import first, then re-added under /auth by the later
// `auth` import (same route names, so it replaces the /{_locale} copy), and
// once more under /old by `legacy`, whose name_prefix keeps its names apart.
class SsoController
{
    #[Route('/sso/login', name: 'sso_login', methods: ['GET'])]
    public function login(): Response
    {
        return new Response();
    }
}
