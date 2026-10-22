@smoke @drupal-qa @user
Feature: Logging in
  Visitors can reach the login form, and a logged-in user reaches their account.

  Scenario: The login page loads
    When I go to "/user/login"
    Then I should get a 200 HTTP response
    And I should see the button "Log in"

  Scenario: Anonymous visitors cannot reach administration
    When I go to "/admin"
    Then I should get a 403 HTTP response

  @api
  Scenario: A logged-in user reaches their account
    Given I am logged in as a new user with the "authenticated" role
    When I go to "/user"
    Then I should get a 200 HTTP response

  Scenario: The password reset form loads
    When I go to "/user/password"
    Then I should get a 200 HTTP response
    And I should see the "form#user-pass" element

  @api
  Scenario: Registration is open only if the site allows it
    Then registration matches the site's setting
