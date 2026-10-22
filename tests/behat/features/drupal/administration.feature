@smoke @drupal-qa @admin @api
Feature: Administration
  The screens editors and administrators use every day load.

  Scenario: The main admin screens load
    Given I am logged in as a new user with the "administrator" role
    When I go to "/admin/content"
    Then I should get a 200 HTTP response
    When I go to "/admin/people"
    Then I should get a 200 HTTP response
    When I go to "/admin/reports/status"
    Then I should get a 200 HTTP response

  Scenario: Every content type's add form loads
    Given I am logged in as a new user with the "administrator" role
    Then every content type's add form loads
