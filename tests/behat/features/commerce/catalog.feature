@smoke @drupal-qa @commerce
Feature: Product catalog
  As a site visitor
  I need to browse products
  So that I can find what I want to purchase

  Scenario: Anonymous user can access the homepage
    Given I am an anonymous user
    When I go to the homepage
    Then I should get a 200 HTTP response

  Scenario: Authenticated user can access the homepage
    Given I am logged in as a user with the "authenticated" role
    When I go to the homepage
    Then I should get a 200 HTTP response
