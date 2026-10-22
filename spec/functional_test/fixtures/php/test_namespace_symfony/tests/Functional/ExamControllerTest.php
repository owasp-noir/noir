<?php

namespace App\Tests\Functional;

use Symfony\Component\Routing\Attribute\Route;

class ExamControllerTest
{
    #[Route('/exam-test-double', name: 'exam_test_double', methods: ['GET'])]
    public function double(): void
    {
    }
}
