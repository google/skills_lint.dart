# suggestions

Picks and formats the "Did you mean ...?" suggestions that rules and
diagnostics show. `closestNames` matches candidate names within a
caller-chosen `maxDistance`, and `didYouMean` formats the question; the
surrounding diagnostic message stays with each caller.

`closestNames` returns every equally close name. Each caller decides what to do
with a tie.
