Feature: The recorded area can be cropped in the editor
  After a recording the user can cut away parts of the screen, for example a
  strip at the top. The video always keeps the shape of the cropped area, so
  the Layout section has no Full screen, Framed or Aspect controls.

  Background:
    Given a recording is open in the editor

  Scenario: The Layout section has no Full screen, Framed or Aspect controls
    When the user looks at the Layout section
    Then there is no "Full screen" button
    And there is no "Framed" button
    And there is no "Aspect" picker
    And there is a "Crop" button

  Scenario: A new recording is not cropped
    Given the recording was never cropped
    Then the whole recorded screen is shown
    And the video has the size of the recorded screen

  Scenario: Crop mode shows the whole recorded screen
    Given the recording is already cropped
    When the user clicks "Crop"
    Then the preview shows the whole recorded screen at the playhead
    And the current crop is drawn as a frame with handles on top of it
    And playback is paused

  Scenario: Dragging the top edge crops from the top
    Given crop mode is open
    When the user drags the top edge down by a quarter of the screen height
    And clicks "Done"
    Then crop mode closes
    And the top quarter of the recording is cut away
    And the video is a quarter less tall and keeps its width

  Scenario: Dragging a corner crops two sides at once
    Given crop mode is open
    When the user drags the bottom right corner up and to the left
    And clicks "Done"
    Then the right and bottom parts are cut away

  Scenario: Dragging inside the crop frame moves it
    Given crop mode is open with a crop smaller than the screen
    When the user drags inside the crop frame
    Then the frame moves without changing its size
    And it stays inside the recorded screen

  Scenario: The crop cannot leave the recorded screen
    Given crop mode is open
    When the user drags an edge past the border of the recorded screen
    Then the edge stops at the border

  Scenario: The crop cannot get smaller than 64 by 64 pixels
    Given crop mode is open
    When the user drags an edge past the opposite edge
    Then the crop stays at least 64 by 64 pixels of the recording

  Scenario: Cancel keeps the previous crop
    Given crop mode is open
    And the user changed the crop frame
    When the user clicks "Cancel" or presses Esc
    Then crop mode closes
    And the crop is unchanged

  Scenario: Reset crop shows the whole screen again
    Given the recording is cropped
    When the user clicks "Reset crop"
    Then the whole recorded screen is shown again
    And the video has the size of the recorded screen

  Scenario: The video keeps the shape of the cropped area
    Given the recording is cropped to a wide strip
    Then the preview and the exported video have the shape of that strip
    And there are no empty bars around it except the chosen spacing

  Scenario: The chosen resolution applies to the cropped area
    Given the recording is cropped
    And the resolution is set to 1080p
    Then the shorter side of the video is 1080 pixels
    And the longer side follows the shape of the crop

  Scenario: Zoom stays inside the cropped area
    Given the recording is cropped
    And a zoom step is active
    Then the zoom only shows parts of the cropped area
    And a zoom that follows the cursor uses the cursor position inside the cropped area

  Scenario: The exported video is cropped
    Given the recording is cropped
    When the user exports the video
    Then the exported video shows only the cropped area

  Scenario: A crop can be undone
    Given the user cropped the recording
    When the user presses Command Z
    Then the previous crop is back

  Scenario: The crop is kept with the recording
    Given the user cropped the recording
    When the user opens the recording again later
    Then it is still cropped

  Scenario: The crop does not carry over to new recordings
    Given the user cropped a recording
    When the user makes a new recording
    Then the new recording is not cropped

  Scenario: Recordings saved with an aspect setting open with their original shape
    Given a recording was saved with the aspect set to 16:9 before this change
    When the user opens it
    Then it opens without an error
    And the video has the shape of the recorded screen
