Feature: Selected area is applied as soon as it is drawn
  The user picks a part of the screen to record. The area is applied when the
  mouse is released, and the white frame that marks the area only shows while
  it is useful.

  Background:
    Given the app is open on the home screen
    And the recording mode "Selected area" is chosen
    And no recording is in progress

  Scenario: Releasing the mouse after a valid drag applies the area
    Given the area picker is open
    When the user drags out an area of at least 64 by 64 and releases the mouse
    Then the picker closes
    And the area is applied
    And no key was pressed

  Scenario: A drag smaller than 64 by 64 keeps the picker open
    Given the area picker is open
    When the user drags out an area smaller than 64 by 64 and releases the mouse
    Then the picker stays open
    And the previous area is unchanged

  Scenario: A click without a drag keeps the picker open
    Given the area picker is open
    When the user clicks without dragging
    Then the picker stays open
    And the previous area is unchanged

  Scenario: The user can try again after a drag that was too small
    Given the area picker is open
    And the user dragged an area that was too small
    When the user drags out a valid area and releases the mouse
    Then only the valid area is applied

  Scenario: Resizing or moving an existing selection applies it on release
    Given the area picker is open with a selection already drawn
    When the user resizes or moves the selection and releases the mouse
    And the result is at least 64 by 64
    Then the picker closes
    And the changed area is applied

  Scenario: Shrinking a selection below the minimum keeps the picker open
    Given the area picker is open with a selection already drawn
    When the user shrinks the selection below 64 by 64 and releases the mouse
    Then the picker stays open

  Scenario: The picker hint mentions no keys
    When the area picker is open
    Then the hint reads "Drag to select an area"
    And the hint does not mention Enter or Esc

  Scenario: Pressing Return does not finish the picker
    Given the area picker is open with a valid selection drawn
    When the user presses Return
    Then the picker stays open

  Scenario: Pressing Esc cancels the picker silently
    Given the area picker is open
    When the user presses Esc
    Then the picker closes
    And no area is applied
    And no message is shown

  Scenario: The frame is shown on the home screen with an active area
    Given an area is active
    When the main window shows the home screen
    Then the area frame is on screen

  Scenario: The frame is hidden while no area is active
    Given no area is active
    Then the area frame is not on screen

  Scenario: The frame is hidden in the editor
    Given an area is active
    When the user opens a recording in the editor
    Then the area frame is not on screen

  Scenario: The frame is hidden while the editor is loading
    Given an area is active
    When a recording has just stopped and the editor is still loading
    Then the area frame is not on screen

  Scenario: The frame is hidden during the countdown
    Given an area is active
    When the recording countdown is running
    Then the area frame is not on screen

  Scenario: The frame is hidden while recording and saving
    Given an area is active
    When a recording is in progress or being saved
    Then the area frame is not on screen

  Scenario: The frame is hidden when the main window is closed
    Given an area is active
    When the user closes the main window
    Then the area frame is not on screen

  Scenario: The frame is hidden when the main window is minimised
    Given an area is active
    When the user minimises the main window
    Then the area frame is not on screen

  Scenario: The frame returns after Back to Recordings
    Given an area is active
    And the user is in the editor
    When the user clicks Back to Recordings
    Then the area frame is on screen

  Scenario: The frame returns after the window is restored
    Given an area is active
    And the main window was closed or minimised
    When the user brings the main window back
    Then the area frame is on screen
