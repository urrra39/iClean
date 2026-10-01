# Homebrew cask template for the menu-bar app. Fill in sha256 for a published,
# notarized release before publishing it in a tap.
cask "iclear-app" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_OF_ICLEAR_ZIP"

  url "https://github.com/urrra39/iClear/releases/download/v#{version}/iClear-#{version}.zip"
  name "iClear"
  desc "Menu bar app that pauses idle background apps under memory pressure"
  homepage "https://github.com/urrra39/iClear"

  depends_on macos: ">= :ventura"

  app "iClear.app"
  binary "#{appdir}/iClear.app/Contents/Helpers/iclear"

  uninstall_preflight do
    system_command "#{appdir}/iClear.app/Contents/Helpers/iclear", args: ["uninstall"]
  end

  zap trash: "~/Library/Application Support/iClear"
end
