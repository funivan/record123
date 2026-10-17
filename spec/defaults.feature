Feature: The home screen starts with useful recording defaults
  A new user can press Record straight away. The main display is recorded in
  full, the MacBook microphone is on and the MacBook camera is shown. A choice
  the user made before is kept.

  Background:
    Given the app is open on the home screen
    And no recording is in progress

  Scenario: The main display is recorded in full by default
    When the app starts
    Then the screen picker shows the main display
    And "Full display" is selected

  Scenario: The chosen display is kept while it is connected
    Given the chosen display is connected
    When the list of displays is refreshed
    Then it stays selected

  Scenario: The main display is picked when the chosen display is gone
    Given the chosen display is no longer connected
    And the main display is connected
    When the list of displays is refreshed
    Then the main display is selected

  Scenario: Another display is picked when neither the chosen nor the main display is available
    Given neither the chosen display nor the main display is in the list
    And another display is connected
    When the list of displays is refreshed
    Then the first display in the list is selected

  Scenario: The display selection is left alone when no display is listed
    Given no display is listed
    When the list of displays is refreshed
    Then the selection is left unchanged

  Scenario: The MacBook microphone is used by default
    Given the user never chose a microphone
    And the MacBook microphone and an iPhone microphone are available
    When the app starts
    Then the audio picker shows the MacBook microphone

  Scenario: The MacBook camera is used by default
    Given the user never chose a camera
    And the MacBook camera and an iPhone camera are available
    When the app starts
    Then the camera picker shows the MacBook camera

  Scenario: The system default device is used when there is no built-in one
    Given the user never chose a camera or microphone
    And no built-in device is available
    And the system has a default device
    When the app starts
    Then the system default device is selected

  Scenario: Nothing is selected when there is no built-in device and no usable system default
    Given the user never chose a device
    And no built-in device is available
    And the system default is missing or not in the list
    When the app starts
    Then nothing is selected

  Scenario: Nothing is selected when no device is available
    Given the user never chose a camera or microphone
    And no device of that kind is available
    When the app starts
    Then "No camera" or "No microphone" is shown

  Scenario: An explicit "No camera" or "No microphone" is kept
    Given the user chose "No camera" or "No microphone" before
    And the MacBook camera and microphone are available
    When the app starts
    Then "No camera" or "No microphone" is still shown

  Scenario: A device the user chose before is kept
    Given the user chose an external microphone before
    And it is still connected
    When the app starts
    Then the external microphone is selected, not the MacBook one

  Scenario: The MacBook device is used when the chosen device is gone
    Given the user chose an external camera or microphone before
    And it is no longer connected
    When the list of devices is refreshed
    Then the MacBook camera or microphone is selected

  Scenario: The system default is used when the chosen device is gone and there is no built-in one
    Given the chosen device is gone
    And there is no built-in device
    When the list of devices is refreshed
    Then the system default is selected, or nothing when it is not available

  Scenario: No device is selected when access is denied
    Given camera or microphone access is denied or restricted for Recordy
    When the list of devices is refreshed
    Then "No camera" or "No microphone" is shown

  Scenario: System audio stays off by default
    Given the user never changed "Record system audio"
    When the app starts
    Then "Record system audio" is off
