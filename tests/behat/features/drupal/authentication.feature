@smoke @drupal-qa @user
Feature: User authentication
  As a site visitor
  I need to log in and access my account
  So that I can manage my profile

  Scenario: Anonymous user can access the login page
    Given I am an anonymous user
    When I go to "/user/login"
    Then I should get a 200 HTTP response
    And I should see "Log in"

  Scenario: Anonymous user cannot access admin pages
    Given I am an anonymous user
    When I go to "/admin"
    Then I should get a 403 HTTP response

  Scenario: Authenticated user can access their profile
    Given I am logged in as a user with the "authenticated" role
    When I go to "/user"
    Then I should get a 200 HTTP response
