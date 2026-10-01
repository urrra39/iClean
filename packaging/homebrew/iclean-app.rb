# Homebrew cask template for the menu-bar app. Fill in sha256 for a published,
# notarized release before publishing it in a tap.
cask "iclean-app" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_OF_ICLEAN_ZIP"

  url "https://github.com/urrra39/iClean/releases/download/v#{version}/iClean-#{version}.zip"
  name "iClean"
  desc "Menu bar app that pauses idle background apps under memory pressure"
  homepage "https://github.com/urrra39/iClean"

  depends_on macos: ">= :ventura"

  app "iClean.app"
  binary "#{appdir}/iClean.app/Contents/Helpers/iclean"

  uninstall_preflight do
    system_command "#{appdir}/iClean.app/Contents/Helpers/iclean", args: ["uninstall"]
  end

  zap trash: "~/Library/Application Support/iClean"
end
