@smoke @drupal-qa @access
Feature: Role-based access control
  As a site administrator
  I need proper access control on sensitive pages
  So that users only see what they are authorized to see

  Scenario: Anonymous user cannot access admin structure
    Given I am an anonymous user
    When I go to "/admin/structure"
    Then I should get a 403 HTTP response

  Scenario: Anonymous user cannot access admin config
    Given I am an anonymous user
    When I go to "/admin/config"
    Then I should get a 403 HTTP response

  Scenario: Anonymous user cannot access admin people
    Given I am an anonymous user
    When I go to "/admin/people"
    Then I should get a 403 HTTP response

  Scenario: Admin user can access admin pages
    Given I am logged in as a user with the "admin" role
    When I go to "/admin"
    Then I should get a 200 HTTP response
    And I should see "Administration"
