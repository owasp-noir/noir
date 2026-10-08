<?php

namespace App\Entity;

use ApiPlatform\Metadata\ApiProperty;
use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Get;
use ApiPlatform\Metadata\GetCollection;

#[ApiResource(
    // Generated item paths use the identifier property's name.
    operations: [new GetCollection(), new Get()],
)]
class Shop
{
    #[ApiProperty(identifier: true)]
    public string $code = '';
}
