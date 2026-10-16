cask "recordy" do
  version "0.0.4"
  sha256 "61c20af11b56016c21f529cd9443d6a6b4f649616d18e79d04f842ce245b60df"

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
