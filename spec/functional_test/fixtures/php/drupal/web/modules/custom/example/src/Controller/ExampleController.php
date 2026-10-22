<?php

namespace Drupal\example\Controller;

use Drupal\Core\Controller\ControllerBase;

/**
 * Returns responses for the Example module routes.
 */
class ExampleController extends ControllerBase {

  public function listing() {
    return ['#markup' => 'Example list'];
  }

  public function view($id) {
    return ['#markup' => 'Example ' . $id];
  }

  public function submit() {
    return ['#markup' => 'Submitted'];
  }

  public function revision($node, $revision) {
    return ['#markup' => 'Revision ' . $revision];
  }

}
