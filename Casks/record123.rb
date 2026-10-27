cask "record123" do
  version "0.1.0"
  sha256 "6f4ea262015610bfefc5dce4a731723b61aaf8385781b1bb6af76719ebca955c"

  url "https://github.com/funivan/record123/releases/download/v#{version}/Record123-#{version}.zip"
  name "Record123"
  desc "Screen recorder with camera overlay, zooms and a built-in editor"
  homepage "https://github.com/funivan/record123"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Record123.app"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Record123.app"]
  end

  uninstall quit: "com.funivan.record123"

  zap trash: [
    "~/Library/Application Support/Record123",
    "~/Library/Preferences/com.funivan.record123.plist",
    "~/Library/Saved Application State/com.funivan.record123.savedState",
  ]
end
