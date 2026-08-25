Work the Kern backlog forward one coherent step, then stop for this iteration.
Pick the first of these that applies and do it fully — do not ask which one.

1. **Something is red.** A CI run failing on any KernAIO repo, a broken build, a
   test that does not pass locally. Read the actual log, fix the cause, push.
2. **Something is unpushed or unfinished.** Run `pnpm status`. Any repository with
   uncommitted or unpushed work gets committed with an honest Conventional Commit
   subject and pushed. Half-built features land without a changeset.
3. **Something finished is unreleased.** A package with a changeset and no publish,
   or a green feature that never went out. Follow `kern-release` and ship it.
4. **Nothing is pending.** Pick one thing from the standing priorities in the
   `kern-plan` skill and cut a slice of it that ships end to end.

Rules for every iteration: no `git add -A`, stage paths by name; the finished bar in
`kern-ship` applies before anything is tagged; if an iteration produces nothing worth
committing, say so in one line rather than inventing work.
