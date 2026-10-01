# Homebrew formula template (builds from source). Fill in url/sha256 for a tagged
# release before publishing it in a tap.
class Iclean < Formula
  desc "Pauses idle background apps under memory pressure, resumes them on switch"
  homepage "https://github.com/urrra39/iClean"
  url "https://github.com/urrra39/iClean/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_SHA256_OF_THE_TAG_TARBALL"
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on macos: :ventura

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/iclean", ".build/release/icleand", ".build/release/ic-hog"
    generate_completions_from_executable(bin/"iclean", "completions")
  end

  def caveats
    <<~EOS
      Start the per-user daemon (Observe mode until you choose Active):
        iclean install
      Remove it again:
        iclean uninstall --purge
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/iclean version")
    assert_match "SIGSTOP/SIGCONT freeze", shell_output("#{bin}/iclean doctor")
  end
end
