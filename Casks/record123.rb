cask "record123" do
  version "0.0.5"
  sha256 "3f26fe19cf79d20904f35c4ed7edd7fa904f9727b347aa33452f569c5a847064"

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
