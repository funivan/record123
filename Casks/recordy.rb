cask "recordy" do
  version "0.0.2"
  sha256 "1d50316eb564e2cf69492d1ab3ab9af2849ac16ac925e8b87bb9cbf0c0a9d8e6"

  url "https://github.com/funivan/recordy/releases/download/v#{version}/Recordy-#{version}.zip"
  name "Recordy"
  desc "Screen recorder with camera overlay, zooms and a built-in editor"
  homepage "https://github.com/funivan/recordy"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Recordy.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Recordy.app"]
  end

  uninstall quit: "com.recordy.app"

  zap trash: [
    "~/Library/Application Support/Recordy",
    "~/Library/Preferences/com.recordy.app.plist",
    "~/Library/Saved Application State/com.recordy.app.savedState",
  ]
end
