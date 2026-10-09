<?php

namespace OCA\Notes\Controller;

use OCP\AppFramework\Controller;
use OCP\AppFramework\Http\Attribute\ApiRoute;
use OCP\AppFramework\Http\Attribute\NoAdminRequired;
use OCP\AppFramework\Http\DataResponse;

class NoteController extends Controller
{
    /**
     * @NoAdminRequired
     */
    public function index(string $category = ''): DataResponse
    {
        return new DataResponse([]);
    }

    #[NoAdminRequired]
    #[ApiRoute(verb: 'GET', url: '/api/{apiVersion}/notes/{id}')]
    public function show(int $id): DataResponse
    {
        return new DataResponse(['id' => $id]);
    }

    #[NoAdminRequired]
    public function create(string $title, string $content): DataResponse
    {
        return new DataResponse([]);
    }

    #[NoAdminRequired]
    public function update(int $id, string $content): DataResponse
    {
        return new DataResponse([]);
    }

    public function destroy(int $id): DataResponse
    {
        return new DataResponse([]);
    }
}
