 Feature: Accessing Information by communicating with the Grid Agent
  Scenario: An User creates a new account
    Given that a user has an email, password and a valid set of geocoordinates
    Then a user account will be created
    Then a random character will be created for this user
    Then then the user, it's characters and everything they can see in their vision
      is then encoded as json to be sent
  Scenario: An User sends an update on it's geolocation
    Given that a user is signed in
    When the user is verified
    Then the user's location is updated
    Given that the difference in vision can be calculated
    Then then select those objects and encode as json to be sent
  Scenario: A User sends a movement direction for a character.
    Given that an user is signed in and this character exists
    Then check if that motion is a valid move
    Then return the change in vision or an error message if it can't be moved
    

