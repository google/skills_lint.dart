# typed: strict
# frozen_string_literal: true

# Homebrew formula for the prebuilt skills_lint executables that
# .github/workflows/release.yaml attaches to each GitHub Release.
# Formula/README.md says how this file is checked and how to update it.
#
# PLACEHOLDER: no release has the executables yet. `version` and every
# `sha256` below are placeholders, so `brew install` fails until the first
# release replaces them. The sha256 placeholders are 64 zeros.
class SkillsLint < Formula
  desc "Linter for AI agent skills (SKILL.md files)"
  homepage "https://github.com/google/skills_lint.dart"
  version "0.5.3" # PLACEHOLDER: set to the first release with executables.
  license "BSD-3-Clause"

  livecheck do
    url :stable
    regex(/^skills_lint-v?(\d+(?:\.\d+)+)$/i)
    strategy :github_latest
  end

  on_macos do
    # The minimum macOS version of the release executables. Keep it equal to
    # macosMinimumVersion in release/lib/src/macho.dart.
    depends_on macos: :sonoma

    on_arm do
      url "https://github.com/google/skills_lint.dart/releases/download/skills_lint-v#{version}/skills_lint-macos-arm64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000" # PLACEHOLDER
    end
    on_intel do
      url "https://github.com/google/skills_lint.dart/releases/download/skills_lint-v#{version}/skills_lint-macos-x64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000" # PLACEHOLDER
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/google/skills_lint.dart/releases/download/skills_lint-v#{version}/skills_lint-linux-arm64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000" # PLACEHOLDER
    end
    on_intel do
      url "https://github.com/google/skills_lint.dart/releases/download/skills_lint-v#{version}/skills_lint-linux-x64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000" # PLACEHOLDER
    end
  end

  def install
    os = OS.mac? ? "macos" : "linux"
    arch = Hardware::CPU.arm? ? "arm64" : "x64"
    bin.install "skills_lint-#{os}-#{arch}" => "skills_lint"
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/skills_lint --version").strip

    (testpath/"skills/my-skill/SKILL.md").write <<~MARKDOWN
      ---
      name: my-skill
      description: A minimal skill that the Homebrew formula test lints.
      ---

      # My skill

      Body.
    MARKDOWN
    assert_match "Skill is valid", shell_output("#{bin}/skills_lint -d #{testpath}/skills")
  end
end
