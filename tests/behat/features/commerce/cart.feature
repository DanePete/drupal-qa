@smoke @drupal-qa @commerce
Feature: Shopping cart
  As a customer
  I need the cart to function correctly
  So that I can manage items before checkout

  Scenario: Anonymous user can access the cart page
    Given I am an anonymous user
    When I go to "/cart"
    Then I should get a 200 HTTP response

  Scenario: Empty cart shows appropriate message
    Given I am logged in as a user with the "authenticated" role
    When I go to "/cart"
    Then I should see "Your cart is empty"
