Feature: The home screen starts with useful recording defaults
  A new user can press Record straight away. The main display is recorded in
  full, the MacBook microphone is on and the MacBook camera is shown. A choice
  the user made before is kept.

  Background:
    Given the app is open on the home screen
    And no recording is in progress

  Rule: The main display is recorded in full by default

    Scenario: A new user records the main display
      When the app starts
      Then the screen picker shows the main display
      And "Full display" is selected

    Scenario: The chosen display is kept while it is connected
      Given the chosen display is connected
      When the list of displays is refreshed
      Then the chosen display stays selected

    Scenario: The main display replaces a display that is gone
      Given the chosen display is no longer connected
      And the main display is connected
      When the list of displays is refreshed
      Then the main display is selected

    Scenario: The first display is used when the main display is not listed
      Given neither the chosen display nor the main display is in the list
      And another display is connected
      When the list of displays is refreshed
      Then the first display in the list is selected

    Scenario: The selection is left alone when no display is listed
      Given no display is listed
      When the list of displays is refreshed
      Then the selection is unchanged

  Rule: The MacBook camera and microphone are used by default

    Scenario Outline: The built-in device wins over other devices
      Given the user never chose a <device>
      And the MacBook <device> and an iPhone <device> are available
      When the app starts
      Then the MacBook <device> is selected

      Examples:
        | device     |
        | camera     |
        | microphone |

    Scenario: The system default is used when there is no built-in device
      Given the user never chose a camera or microphone
      And no built-in device is available
      And the system has a default device
      When the app starts
      Then the system default device is selected

    Scenario: Nothing is selected without a built-in device or a usable system default
      Given the user never chose a camera or microphone
      And no built-in device is available
      And the system default is missing or not in the list
      When the app starts
      Then nothing is selected

    Scenario Outline: Nothing is shown when no device exists
      Given the user never chose a <device>
      And no <device> is available
      When the app starts
      Then "<label>" is shown

      Examples:
        | device     | label         |
        | camera     | No camera     |
        | microphone | No microphone |

  Rule: A choice the user made before is respected

    Scenario Outline: An explicit "none" is kept
      Given the user chose "<label>" before
      And the MacBook <device> is available
      When the app starts
      Then "<label>" is still shown

      Examples:
        | device     | label         |
        | camera     | No camera     |
        | microphone | No microphone |

    Scenario: A chosen device is kept while it is connected
      Given the user chose an external microphone before
      And it is still connected
      When the app starts
      Then the external microphone is selected
      But the MacBook microphone is not

    Scenario: The MacBook device replaces a chosen device that is gone
      Given the user chose an external camera or microphone before
      And it is no longer connected
      When the list of devices is refreshed
      Then the MacBook camera or microphone is selected

    Scenario: The system default replaces a chosen device that is gone
      Given the chosen device is no longer connected
      And there is no built-in device
      When the list of devices is refreshed
      Then the system default is selected, or nothing when it is not available

  Rule: Denied access selects nothing

    Scenario Outline: A denied or restricted device is not selected
      Given <device> access is denied or restricted for Recordy
      When the list of devices is refreshed
      Then "<label>" is shown

      Examples:
        | device     | label         |
        | camera     | No camera     |
        | microphone | No microphone |

  Rule: System audio is off by default

    Scenario: System audio stays off
      Given the user never changed "Record system audio"
      When the app starts
      Then "Record system audio" is off
