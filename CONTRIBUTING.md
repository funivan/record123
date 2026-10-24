# Contributing

Thanks for helping with Record123.

## Set up

Requires macOS 14+ and Xcode command line tools with Swift 5.9 or later.

```sh
git clone git@github.com:funivan/record123.git
cd record123
./build.sh --full
```

`--full` builds `Record123.app`, quits a running copy and relaunches it.

## Permissions while developing

macOS ties Screen Recording, Camera and Microphone permissions to the app's signing identity. Ad-hoc builds get a new identity every time, so permissions reset on each rebuild. Create a local code signing certificate named `Record123 Local Signing` in your keychain and `build.sh` will use it automatically.

## Where things live

- `Sources/Record123`: the SwiftUI app
- `Resources`: app icon and bundled wallpapers
- `tools`: scripts that regenerate the icon and wallpapers

## Sending changes

- Branch from `main` and keep each pull request focused on one change
- Make sure `./build.sh` succeeds before opening the pull request
- Describe what changed and why, and attach a screenshot or short clip for UI changes
- Follow the style of the surrounding code and avoid comments that restate what the code does

## Reporting bugs

Open an [issue](https://github.com/funivan/record123/issues) with your macOS version, chip (Apple silicon or Intel), and steps to reproduce.

## Tests

Run `swift test`. CI runs the same command on every pull request.


