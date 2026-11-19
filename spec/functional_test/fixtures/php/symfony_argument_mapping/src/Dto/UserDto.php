<?php
namespace App\Dto;

class UserDto
{
    public function __construct(
        public readonly string $name,
        public readonly string $email,
        public readonly ?int $age = null,
    ) {}
}
