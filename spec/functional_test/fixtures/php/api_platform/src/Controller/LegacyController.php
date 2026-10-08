<?php

namespace App\Controller;

use ApiPlatform\Validator\ValidatorInterface;
use FOS\RestBundle\Controller\Annotations\Get;
use OpenApi\Attributes as OA;

// Attributes from other libraries are not API Platform resources, whether on
// a method or (swagger-php) on the class.
#[OA\Get(path: '/legacy/foo')]
class LegacyController
{
    #[Get('/legacy/ping')]
    public function ping(): string
    {
        return 'pong';
    }
}
