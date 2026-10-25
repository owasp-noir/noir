<?php

namespace App\Support;

trait ReadsInput
{
    public function readString(string $field): string
    {
        return (string) $this->get($field);
    }
}
