@smoke @drupal-qa @content
Feature: Content pages
  As a site visitor
  I need core pages to load correctly
  So that I can browse the site

  Scenario: Homepage returns 200
    Given I am an anonymous user
    When I go to the homepage
    Then I should get a 200 HTTP response

  Scenario: Authenticated user can access the homepage
    Given I am logged in as a user with the "authenticated" role
    When I go to the homepage
    Then I should get a 200 HTTP response

  Scenario: 404 page returns proper status code
    Given I am an anonymous user
    When I go to "/this-page-definitely-does-not-exist-12345"
    Then I should get a 404 HTTP response
