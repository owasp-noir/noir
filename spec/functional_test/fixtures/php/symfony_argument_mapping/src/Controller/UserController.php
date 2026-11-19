<?php
namespace App\Controller;

use App\Dto\UserDto;
use Symfony\Component\HttpFoundation\File\UploadedFile;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpKernel\Attribute\MapQueryParameter;
use Symfony\Component\HttpKernel\Attribute\MapQueryString;
use Symfony\Component\HttpKernel\Attribute\MapRequestPayload;
use Symfony\Component\HttpKernel\Attribute\MapUploadedFile;
use Symfony\Component\Security\Http\Attribute\CurrentUser;
use Symfony\Component\Routing\Attribute\Route;

class UserController
{
    #[Route('/control', methods: ['GET'])]
    public function control(Request $request): Response
    {
        return new Response($request->query->get('q'));
    }

    #[Route('/search', methods: ['GET'])]
    public function search(
        #[MapQueryParameter] string $term,
        #[MapQueryParameter(name: 'per-page')] int $perPage = 10,
    ): Response { return new Response(''); }

    #[Route('/filter', methods: ['GET'])]
    public function filter(#[MapQueryString] UserDto $filter): Response { return new Response(''); }

    #[Route('/users', methods: ['POST'])]
    public function create(#[MapRequestPayload] UserDto $user): Response { return new Response(''); }

    #[Route('/avatar', methods: ['POST'])]
    public function avatar(#[MapUploadedFile] UploadedFile $picture): Response { return new Response(''); }

    #[Route('/payload', methods: ['POST'])]
    public function payload(Request $request): Response
    {
        return new Response($request->getPayload()->get('title'));
    }

    // Neither a request-mapping attribute nor a DTO in the tree: no params.
    #[Route('/me', methods: ['POST'])]
    public function me(#[CurrentUser] $user, #[MapRequestPayload] \Vendor\Missing $payload): Response { return new Response(''); }
}
