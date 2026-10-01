# GitHub Actions verification policy

The `FPGA Verification` workflow deliberately separates fast feedback from the
complete pull-request gate. This avoids running the same 40–50 minute suite for
both a feature-branch push and the pull request created from that commit. It
does not remove tests from the authoritative local or pull-request regression.

## Audit and baseline

Before this change, every push on every branch and every pull request to
`main` ran the same single `verification` job and `scripts/test.sh`. There was
no manual trigger, concurrency cancellation, job timeout, or installed-tool
cache. Python 3.12 dependency caching was already enabled. Each clean hosted
run rebuilt Verilator 5.032 from its pinned immutable upstream commit; Quartus
was not and is not run on the hosted Linux runner.

On the development host, the pre-change components measured approximately 33
seconds for 1,381 Python tests, 4 seconds for complete Verilator lint, 832
seconds for `scripts/sim.sh` with warm generated models, and 391 seconds for the
dedicated debugger regression. The RTL simulations dominate the verification
runtime; a clean hosted run also pays compilation and Verilator installation
costs. This matches the observed 40–50 minute hosted runs and confirms that the
feature push and pull-request events were duplicating the expensive full suite.

## Verification levels

| Event | Level | Command | Purpose |
| --- | --- | --- | --- |
| Feature-branch push | FAST | `scripts/test_fast.sh` | Complete Python tests, complete Verilator lint, and focused platform plus Phase 4F-A/B/C RTL smoke |
| Pull request to `main` | FULL | `scripts/test.sh` | Required complete Python, lint, RTL, CPU, PPU, bus, cartridge, controller, DMA, video, Developer Mode, debugger, runtime-loader, and integration regression |
| GitHub-generated PR merge pushed to `main` | FAST | `scripts/test_fast.sh` | Integrity check for a tree already covered by the full PR gate |
| Direct or nonstandard push to `main` | FULL | `scripts/test.sh` | Fail-safe coverage if `main` changes without the normal protected-PR path |
| `release/**` branch or tag push | FULL | `scripts/test.sh` | Release verification |
| Manual dispatch | FULL by default, FAST optional | selected script | Explicit operator verification |

The workflow keeps the existing `verification` job/check identity so the full
pull-request gate remains compatible with branch protection. A 75-minute job
timeout stops stuck simulations while leaving substantial margin above the
observed 40–50 minute full runtime. Per-PR concurrency cancels an obsolete run
when a newer commit is pushed to the same PR; branch, tag, and manual runs use
their Git ref as the concurrency key.

GitHub-generated merges are recognized conservatively: both the standard
`web-flow` committer identity and `Merge pull request #...` subject must match.
If either is absent, a push to `main` receives FULL verification.

## Caching and paths

Python dependency caching remains keyed by `requirements-dev.txt`. The workflow
also caches only the installed Verilator 5.032 toolchain, keyed by runner OS,
architecture, version, and the immutable upstream release commit. It does not
cache generated vectors, Verilated models, simulation outputs, or synthesis
outputs, so stale build products cannot hide RTL changes.

No `paths-ignore` filter is used. Documentation-only changes still create the
normal check, avoiding required-check ambiguity and conservatively covering
documentation that describes commands, constraints, configuration, or release
procedures. Quartus remains a local gate because the hosted runner does not
contain Intel's toolchain.

## Local verification

`scripts/test.sh` remains the complete local regression and is unchanged as the
FULL entry point. `scripts/sim.sh` still defaults to all simulations; its new
`--fast` option runs only the platform and Phase 4F-A/B/C unit smoke used by
FAST CI. The normal pre-push sequence remains the complete regression, complete
Verilator lint, Quartus build, and timing review.

For a normal feature cycle, expected hosted usage changes from two full runs
(about 90–100 Linux minutes) to one short FAST push run plus one 40–50 minute
FULL pull-request run. A warm Verilator cache should keep FAST near a few
minutes, for an expected warm total near 42–55 minutes. The first run for a new
cache key also builds the pinned toolchain, so a cold cycle may be closer to
50–65 minutes. The exact hosted value is recorded by Actions.
