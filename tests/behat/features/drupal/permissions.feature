@smoke @drupal-qa @access @api
Feature: Safe roles
  Visitors and ordinary users can't do what only administrators should.

  Scenario: Visitors and ordinary users hold no restricted permissions
    Then visitors and ordinary users hold no restricted permissions
