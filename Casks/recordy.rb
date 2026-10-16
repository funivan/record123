cask "recordy" do
  version "0.0.5"
  sha256 "3f26fe19cf79d20904f35c4ed7edd7fa904f9727b347aa33452f569c5a847064"

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

  uninstall quit: "com.funivan.recordy"

  zap trash: [
    "~/Library/Application Support/Recordy",
    "~/Library/Preferences/com.funivan.recordy.plist",
    "~/Library/Saved Application State/com.funivan.recordy.savedState",
  ]
end
