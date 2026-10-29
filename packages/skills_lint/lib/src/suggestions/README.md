# suggestions

Picks the "Did you mean" suggestions that rules and diagnostics show.
It is separate so all of them share one matcher and one closeness threshold.
Only code that chooses a suggestion belongs here, not message wording.

`closestNames` returns every equally close name. Each caller decides what to do
with a tie: a rule-name message lists them all, and a file or directory
suggestion shows none, so a broken link never gets a guessed fix.
