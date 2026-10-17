import Testing
import Foundation
@testable import Recordy

/*
Feature: The background is one choice of wallpaper, gradient or image
  The Background panel shows one section per type. Choosing a type replaces
  the previous background, and a project saved before the type existed keeps
  the background it had.
*/
struct BackgroundModeTests {
    /*
    Scenario: Choosing a gradient background removes the image
      Given the background is a wallpaper
      When the user chooses the gradient type
      Then the background is a gradient
      And no image is set
    */
    @Test("Choosing a gradient background removes the image")
    func gradientRemovesImage() {
        var style = Style()
        style.selectBackground(.wallpaper)
        style.bgImageFile = "wallpaper.jpg"

        style.selectBackground(.gradient)

        #expect(style.bgMode == .gradient)
        #expect(style.bgGradient == true)
        #expect(style.bgImageFile == nil)
    }

    /*
    Scenario: Choosing a wallpaper sets the image and keeps the type
      Given the background is a gradient
      When the user chooses a wallpaper
      Then the background is that wallpaper
      And the type is wallpaper
    */
    @Test("Choosing a wallpaper sets the image and keeps the type")
    func wallpaperSetsImage() {
        var style = Style()
        style.selectBackground(.gradient)

        style.selectBackground(.wallpaper)
        style.bgImageFile = "wallpaper.jpg"

        #expect(style.bgMode == .wallpaper)
        #expect(style.bgImageFile == "wallpaper.jpg")
    }

    /*
    Scenario: A project saved before the type existed with an image is shown as an image
      Given a saved style has an image file and no type
      When the project is loaded
      Then the type is image
    */
    @Test("A project saved before the type existed with an image is shown as an image")
    func legacyImageDecodesAsImage() throws {
        let json = #"{"bgImageFile":"background-1.jpg","bgGradient":true}"#.data(using: .utf8)!

        let style = try JSONDecoder().decode(Style.self, from: json)

        #expect(style.bgMode == .image)
    }

    /*
    Scenario: A project saved with a solid colour keeps its look as a gradient
      Given a saved style has no image file, the gradient is off and the colour is red
      When the project is loaded
      Then the type is gradient
      And both gradient colours are red
    */
    @Test("A project saved with a solid colour keeps its look as a gradient")
    func legacySolidBecomesFlatGradient() throws {
        let json = #"{"bgGradient":false,"bgColor1":{"r":1,"g":0,"b":0,"a":1},"bgColor2":{"r":0,"g":0,"b":1,"a":1}}"#.data(using: .utf8)!

        let style = try JSONDecoder().decode(Style.self, from: json)

        #expect(style.bgMode == .gradient)
        #expect(style.bgGradient == true)
        #expect(style.bgColor2 == style.bgColor1)
    }

    /*
    Scenario: A new project starts with the blue and yellow dotted wallpaper
      Given a new project
      When the editor opens it
      Then the background is the blue and yellow halftone wallpaper
    */
    @Test("A new project starts with the blue and yellow dotted wallpaper")
    func defaultWallpaper() {
        let style = Style()

        #expect(style.bgMode == .wallpaper)
        #expect(style.bgImageFile == "27-ukraine-halftone.jpg")
    }

    /*
    Scenario: The pattern only applies to a gradient
      Given the background is a gradient with the lines pattern
      When the user chooses the wallpaper type
      Then no pattern is set
    */
    @Test("The pattern only applies to a gradient")
    func patternClearedOutsideGradient() {
        var style = Style()
        style.selectBackground(.gradient)
        style.bgPattern = .lines

        style.selectBackground(.wallpaper)

        #expect(style.bgPattern == .none)
    }
}
