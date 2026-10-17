Feature: Selected area is applied as soon as it is drawn
  The user picks a part of the screen to record. The area is applied when the
  mouse is released, and the white frame that marks the area only shows while
  it is useful.

  Background:
    Given the app is open on the home screen
    And the recording mode "Selected area" is chosen
    And no recording is in progress

  Rule: The area is applied when the mouse is released

    Scenario: A valid drag applies the area
      Given the area picker is open
      When the user drags out an area of at least 64 by 64 and releases the mouse
      Then the picker closes
      And the area is applied
      But no key was pressed

    Scenario Outline: A drag that is too small keeps the picker open
      Given the area picker is open
      And an area is already applied
      When the user drags out an area of <width> by <height> and releases the mouse
      Then the picker stays open
      And the applied area is unchanged

      Examples:
        | width | height |
        | 63    | 63     |
        | 63    | 200    |
        | 200   | 10     |

    Scenario: A click without a drag keeps the picker open
      Given the area picker is open
      When the user clicks without dragging
      Then the picker stays open

    Scenario: The user can try again after a drag that was too small
      Given the area picker is open
      And the user dragged an area that was too small
      When the user drags out a valid area and releases the mouse
      Then only the valid area is applied

    Scenario: Resizing or moving a selection applies it on release
      Given the area picker is open with a selection already drawn
      When the user resizes or moves the selection to at least 64 by 64 and releases the mouse
      Then the picker closes
      And the changed area is applied

    Scenario: Shrinking a selection below the minimum keeps the picker open
      Given the area picker is open with a selection already drawn
      When the user shrinks the selection below 64 by 64 and releases the mouse
      Then the picker stays open

  Rule: The picker needs no keys

    @manual
    Scenario: The hint mentions no keys
      When the area picker is open
      Then the hint reads "Drag to select an area"
      But the hint does not mention Enter or Esc

    Scenario: Return does not finish the picker
      Given the area picker is open with a valid selection drawn
      When the user presses Return
      Then the picker stays open

    Scenario: Esc cancels the picker silently
      Given the area picker is open
      When the user presses Esc
      Then the picker closes
      And no area is applied
      But no message is shown

  Rule: The frame is shown only on the home screen with an active area

    Scenario: The frame is shown on the home screen
      Given an area is active
      When the main window shows the home screen
      Then the area frame is on screen

    Scenario: The frame is hidden while no area is active
      Given no area is active
      When the main window shows the home screen
      Then the area frame is not on screen

    Scenario Outline: The frame is hidden while the app is busy
      Given an area is active
      When <situation>
      Then the area frame is not on screen

      Examples:
        | situation                                              |
        | the user opens a recording in the editor               |
        | a recording has stopped and the editor is still loading |
        | the recording countdown is running                     |
        | a recording is in progress                             |
        | a recording is being saved                             |

    @ui
    Scenario Outline: The frame is hidden when the main window is not visible
      Given an area is active
      When the user <action> the main window
      Then the area frame is not on screen

      Examples:
        | action     |
        | closes     |
        | minimises  |

    @ui
    Scenario: The frame returns after Back to Recordings
      Given an area is active
      And the user is in the editor
      When the user clicks Back to Recordings
      Then the area frame is on screen

    @ui
    Scenario: The frame returns after the window is restored
      Given an area is active
      And the main window was closed or minimised
      When the user brings the main window back
      Then the area frame is on screen
