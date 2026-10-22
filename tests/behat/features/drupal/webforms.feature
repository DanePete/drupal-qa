@smoke @drupal-qa @webform @api
Feature: Webforms
  Every open webform loads and can be filled in. Nothing is submitted.

  Scenario: Open webforms load with their submit button
    Given I am logged in as a new user with the "administrator" role
    Then every open webform loads with a submit button
