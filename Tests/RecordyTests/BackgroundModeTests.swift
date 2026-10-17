import Testing
import Foundation
@testable import Recordy

/*
Feature: The background is one choice of solid, gradient, wallpaper or image
  The Background panel shows one section per type. Choosing a type replaces
  the previous background, and a project saved before the type existed keeps
  the background it had.
*/
struct BackgroundModeTests {
    /*
    Scenario: Choosing a solid background removes the image and turns off the gradient
      Given the background is a wallpaper
      When the user chooses the solid type
      Then the background is a solid colour
      And no image is set
    */
    @Test("Choosing a solid background removes the image and turns off the gradient")
    func solidRemovesImage() {
        var style = Style()
        style.selectBackground(.wallpaper)
        style.bgImageFile = "wallpaper.jpg"

        style.selectBackground(.solid)

        #expect(style.bgMode == .solid)
        #expect(style.bgGradient == false)
        #expect(style.bgImageFile == nil)
    }

    /*
    Scenario: Choosing a wallpaper sets the image and keeps the type
      Given the background is a solid colour
      When the user chooses a wallpaper
      Then the background is that wallpaper
      And the type is wallpaper
    */
    @Test("Choosing a wallpaper sets the image and keeps the type")
    func wallpaperSetsImage() {
        var style = Style()
        style.selectBackground(.solid)

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
    Scenario: A project saved before the type existed without an image is shown as a solid colour when the gradient is off
      Given a saved style has no image file, the gradient is off and no type
      When the project is loaded
      Then the type is solid
    */
    @Test("A project saved before the type existed without an image is shown as a solid colour when the gradient is off")
    func legacySolidDecodesAsSolid() throws {
        let json = #"{"bgGradient":false}"#.data(using: .utf8)!

        let style = try JSONDecoder().decode(Style.self, from: json)

        #expect(style.bgMode == .solid)
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
}
