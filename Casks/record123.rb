cask "record123" do
  version "0.1.1"
  sha256 "ba5d883748efa8cdcb9ac9bee556d61b6c6741589da59e161124100ac173c70b"

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
