<?php
// Regression guard: PHPUnit suites live under `tests/` (Laravel/
// CakePHP/PHPUnit default) or `Tests/` (Symfony PSR-4 convention).
// Routes declared inside these classes serve the test suite, never
// real traffic. Neither URL below should appear in the fixture's
// expected-endpoints list.
namespace App\Tests\Controller;

use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;
use Symfony\Component\Routing\Annotation\Route;

class UserControllerTest extends WebTestCase
{
    #[Route('/should-not-appear-tests-dir', methods: ['GET'])]
    public function shouldNotAppearGet(): void {}

    #[Route('/should-not-appear-tests-dir', methods: ['POST'])]
    public function shouldNotAppearPost(): void {}
}
