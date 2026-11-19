<?php
namespace App\Controller;

use FOS\RestBundle\Controller\AbstractFOSRestController;
use FOS\RestBundle\Controller\Annotations as Rest;
use FOS\RestBundle\Controller\Annotations\Delete;
use Symfony\Component\HttpFoundation\Response;

#[Rest\Route('/api')]
class UserApiController extends AbstractFOSRestController
{
    #[Rest\Route('/aliased-route', methods: ['GET'])]
    public function aliased(): Response { return new Response(''); }

    #[Rest\Get('/users/{id}', requirements: ['id' => '\d+'])]
    public function getUserAction(int $id): Response { return new Response(''); }

    #[Rest\Post('/users')]
    #[Rest\RequestParam(name: 'email')]
    public function postUserAction(): Response { return new Response(''); }

    /**
     * @Rest\Put("/users/{id}")
     * @Rest\QueryParam(name="notify", default="1")
     */
    public function putUserAction(int $id): Response { return new Response(''); }

    #[Delete('/users/{id}')]
    public function deleteUserAction(int $id): Response { return new Response(''); }

    // Not imported: `App\Controller\Post`, not FOSRest's.
    #[Post('/unimported')]
    public function unimported(): Response { return new Response(''); }
}
