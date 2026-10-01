# Homebrew formula template (builds from source). Fill in url/sha256 for a tagged
# release before publishing it in a tap.
class Iclear < Formula
  desc "Pauses idle background apps under memory pressure, resumes them on switch"
  homepage "https://github.com/urrra39/iClear"
  url "https://github.com/urrra39/iClear/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_SHA256_OF_THE_TAG_TARBALL"
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on macos: :ventura

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/iclear", ".build/release/icleard", ".build/release/ic-hog"
    generate_completions_from_executable(bin/"iclear", "completions")
  end

  def caveats
    <<~EOS
      Start the per-user daemon (Observe mode until you choose Active):
        iclear install
      Remove it again:
        iclear uninstall --purge
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/iclear version")
    assert_match "SIGSTOP/SIGCONT freeze", shell_output("#{bin}/iclear doctor")
  end
end
