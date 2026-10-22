<?php

namespace App\Entity;

use ApiPlatform\Metadata\ApiResource;

#[ApiResource]
enum BookCondition: string
{
    case New = 'new';
    case Used = 'used';
}
