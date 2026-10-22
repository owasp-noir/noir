<?php

namespace App\Entity;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\GetCollection;

// The standalone operation joins the resource above it (inheriting its
// routePrefix), and replaces the default operations.
#[ApiResource(routePrefix: '/catalog')]
#[GetCollection]
class Publisher
{
}
