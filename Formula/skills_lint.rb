# typed: strict
# frozen_string_literal: true

# Generated from release/templates/skills_lint.rb.tmpl. To change it, edit the
# template and run `dart run bin/release.dart homebrew-formula` in release/.
class SkillsLint < Formula
  desc "Linter for AI agent skills (SKILL.md files)"
  homepage "https://github.com/google/skills_lint.dart"
  version "0.5.3"
  license "BSD-3-Clause"

  livecheck do
    url :stable
    regex(/^skills_lint-v?(\d+(?:\.\d+)+(?:\+\d+)?)$/i)
    strategy :github_latest
  end

  on_macos do
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
    on_intel do
      url "https://github.com/google/skills_lint.dart/releases/download/skills_lint-v#{version}/skills_lint-linux-x64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000" # PLACEHOLDER
    end
    on_arm do
      url "https://github.com/google/skills_lint.dart/releases/download/skills_lint-v#{version}/skills_lint-linux-arm64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000" # PLACEHOLDER
    end
  end

  def install
    # The archive holds LICENSE and one executable for this platform.
    bin.install Dir["skills_lint-*"].first => "skills_lint"
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
