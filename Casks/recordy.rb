cask "recordy" do
  version "0.0.3"
  sha256 "de99e5b680a0b221d90c55388104267a80dacb427004655ee5b190658c43d7aa"

  url "https://github.com/funivan/recordy/releases/download/v#{version}/Recordy-#{version}.zip"
  name "Recordy"
  desc "Screen recorder with camera overlay, zooms and a built-in editor"
  homepage "https://github.com/funivan/recordy"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Recordy.app"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Recordy.app"]
  end

  uninstall quit: "com.recordy.app"

  zap trash: [
    "~/Library/Application Support/Recordy",
    "~/Library/Preferences/com.recordy.app.plist",
    "~/Library/Saved Application State/com.recordy.app.savedState",
  ]
end
