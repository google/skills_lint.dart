# typed: strict
# frozen_string_literal: true

# Homebrew formula for the prebuilt skills_lint executables that
# .github/workflows/release.yaml attaches to each GitHub Release.
#
# PLACEHOLDER: no release has the executables yet. `version` and every
# `sha256` below are placeholders, so `brew install` fails its checksum check
# until the first release replaces them. The sha256 placeholders are 64 zeros.
class SkillsLint < Formula
  desc "Linter for AI agent skills (SKILL.md files)"
  homepage "https://github.com/google/skills_lint.dart"
  version "0.5.3" # PLACEHOLDER: set to the first release with executables.
  license "BSD-3-Clause"

  livecheck do
    url :stable
    regex(/^skills_lint-v?(\d+(?:\.\d+)+)$/i)
  end

  depends_on macos: :sonoma

  on_macos do
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
    (testpath/"skills/my-skill/SKILL.md").write <<~MARKDOWN
      ---
      name: my-skill
      description: A minimal skill that the Homebrew formula test lints.
      ---

      # My skill

      Body.
    MARKDOWN
    assert_match "--skills-directory", shell_output("#{bin}/skills_lint --help")
    assert_match "Skill is valid", shell_output("#{bin}/skills_lint -d #{testpath}/skills")
  end
end
