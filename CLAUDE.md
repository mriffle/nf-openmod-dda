# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Maintenance rule:** Keep this file current. Whenever you change the project's
> purpose, architecture, control flow, conventions, development rules, testing
> approach, or resolve/discover an issue, update the relevant section here in the
> same change. The Open Issues tracker at the bottom must reflect reality — move
> items to Resolved when fixed, add new ones when found. This file is the single
> source of truth for onboarding, architecture, and project conventions.

## Purpose

`nf-openmod-dda` is a Nextflow DSL2 pipeline for **open-modification DDA
proteomics** built around the **Magnum** search engine. It automates the
end-to-end path that is otherwise run by hand and is error-prone to reproduce:
acquire inputs (locally or from PanoramaWeb) → convert vendor RAW to mzML →
prepare per-sample Magnum config → validate/generate FASTA decoys → run Magnum →
post-process with Percolator → optionally convert to Limelight XML and upload.
Everything runs in containers so the toolchain needs no host installs, and the
same workflow runs locally, on Slurm, or on AWS Batch. It is a workflow
implementation, not a general proteomics library.

## Commands

Runs are profile-driven. The `standard` profile (local executor) is applied
automatically when `-profile` is omitted.

```bash
# Run the workflow (combined mode is the default; -c supplies params)
nextflow run main.nf -profile standard -c <config>

# Other executors
nextflow run main.nf -profile aws   -c <config>   # AWS Batch
nextflow run main.nf -profile slurm -c <config>   # Slurm

# Wiring/control-flow tests (no real tools; what CI's stub job runs)
nextflow run main.nf -profile standard -stub -c conf/test_combined.config
nextflow run main.nf -profile standard -stub -c conf/test_separate.config

# Real-data end-to-end smoke tests (what CI's smoke matrix runs; needs Docker)
nextflow run main.nf -profile standard -c conf/smoke_single_decoys.config   # any conf/smoke_*.config

# Fast parse + DAG check after editing .nf files — validates wiring without
# pulling containers or executing tasks
nextflow run main.nf -profile standard -stub -preview -c conf/test_combined.config

# Secrets must exist before a run touches Panorama/Limelight (CI seeds placeholders)
nextflow secrets set PANORAMA_API_KEY "..."
nextflow secrets set LIMELIGHT_SUBMIT_UPLOAD_KEY "..."

# Docs (Sphinx)
cd docs && make html
```

### Test harness (Docker-free, multi-version)

`test/run-tests.sh` is the self-contained test harness and the primary way to
validate changes locally. It **downloads the Nextflow launcher and each pinned
engine version into a local, git-ignored directory** (`test/.nextflow-dist/`,
used as `NXF_HOME`) and runs everything in scratch dirs under `test/.work/`, so
it never pollutes the repo root and needs nothing pre-installed but `bash`,
`curl`, and a JDK. It does **not** use Docker.

```bash
test/run-tests.sh                                      # lint + tests on all pinned versions
NXF_TEST_VERSIONS="25.10.4 26.04.0" test/run-tests.sh  # override versions (first entry = floor)
```

Per version it runs: `nextflow lint` (must be error-free), stub workflow runs of
combined + separate mode, and the **real** `FILTER_PIN_COLUMNS` and
`VALIDATE_DECOY_OPTIONS` processes (host-executed via tiny drivers in
`test/drivers/`, no container). See Testing for coverage. The same script runs
identically on any machine and in CI.

## Architecture

Four layers, in source-of-truth order (most authoritative first):
`main.nf` (routing) → `workflows/*.nf` (mode strategies) → `modules/*.nf`
(one process each) → config layer (`nextflow.config`, `conf/base.config`,
`container_images.config`, `nextflow_schema.json`).

**Conceptual pipeline order** (`main.nf` then a subworkflow):
1. Resolve `fasta`, `magnum_conf`, `spectra_dir` (local or PanoramaWeb).
2. `VALIDATE_DECOY_OPTIONS` — fail early on inconsistent decoy settings.
3. If `generate_decoys`, run `YARP` to produce a decoy-augmented FASTA.
4. If spectra are RAW, `MSCONVERT` → mzML (skipped when mzML already present).
5. `ADD_PARAMS_TO_MAGNUM_CONF` — inject FASTA + mzML paths into a per-sample conf.
6. `MAGNUM` per sample → PepXML + Percolator-input (`.perc.txt`).
7. Optional `FILTER_PIN_COLUMNS`; combined mode also `COMBINE_PIN_FILES`.
8. `PERCOLATOR` (once on merged input, or once per sample).
9. Optional Limelight XML conversion + upload.
10. Optional completion email (`workflow.onComplete`).

**Combined vs separate is the central branching dimension** (`process_separately`)
and the thing most easily broken by careless edits:

- **Combined** (`process_separately=false`, `workflows/magnum_percolator_combined.nf`):
  Magnum runs per sample, all PIN files are `.collect()`ed and merged
  (`COMBINE_PIN_FILES`), Percolator runs **once** on the merged input, and a single
  Limelight XML/upload is produced. The combined sample id is the literal `"combined"`.
- **Separate** (`process_separately=true`, `workflows/magnum_percolator_separate.nf`):
  keyed `tuple(sample_id, ...)` are preserved end-to-end; Percolator and Limelight
  run per sample, paired via `.join()` on `sample_id`.

## Data & channel patterns

- Data flows as `tuple(sample_id, ...)` where `sample_id` is the file basename.
  Mode-specific `.join()` / `.collect()` depend on these keys — **do not change
  tuple shapes casually**.
- **Single artifacts must stay value channels.** `fasta`, `magnum_conf`, and the
  YARP decoy FASTA broadcast across the per-sample fan-out *because* they derive
  from value/param inputs (a process with no queue-channel inputs emits a value
  channel, which is reusable/broadcast). Do not transform them into single-element
  queue channels — that would silently collapse the fan-out so only one sample is
  processed, and tests asserting only "completed" would not catch it.
- Combined mode intentionally collects before Percolator/Limelight; separate mode
  intentionally preserves keyed tuples. Keep that intent when refactoring.

## Development rules

- **Container images are indirection.** Each module declares
  `container params.images.<key>`; the mapping lives in `container_images.config`.
  Change image tags there, not in module bodies. **Every process must have a
  container directive** — the `aws` (awsbatch) executor cannot submit a containerless
  job. Shell-only helpers use `params.images.ubuntu`.
- **Resources are label-driven** in `conf/base.config` (`withLabel:` blocks). A
  process may carry several labels; when more than one sets the same directive, the
  block declared **last** in `base.config` wins (e.g. `process_high_memory`'s 40 GB
  overrides `process_low`'s memory). Each profile sets `process.resourceLimits`
  (a `[ cpus:, memory:, time: ]` map in `nextflow.config`, and in each `conf/*.config`)
  which clamps every request to the executor's real ceiling — so labels can request
  generously. Prefer changing config over module logic for image/resource changes.
- **Parameter schema is a contract.** `validateParameters()` (nf-schema) runs at
  startup against `nextflow_schema.json`. Any param add/remove/rename/type/default
  change must be mirrored there in the same change, and kept consistent with
  `nextflow.config` defaults, the docs (`README.md`, `docs/source/*`), and the
  `conf/*.config` test configs. Run the stub tests after schema-affecting changes.
- **Secrets** (`PANORAMA_API_KEY`, `LIMELIGHT_SUBMIT_UPLOAD_KEY`) are loaded in
  `nextflow.config` and exposed as env vars (this indirection exists because secrets
  aren't usable directly on AWS Batch). Treat credential handling as part of the
  runtime model, not ordinary input.
- **Remote inputs:** any path starting with `https://` is a PanoramaWeb WebDAV URL.
  `spectra_dir` uses `.contains("https://")`; `fasta`/`magnum_conf` use `.startsWith`.
  Panorama retrieval only enumerates/downloads `.raw`, never mzML.
- **RAW vs mzML:** for a local `spectra_dir`, if any `.mzML` exist they are used
  directly; otherwise `.raw` are converted via msconvert. mzML silently wins when both
  are present.
- **`storeDir` caching** (MSCONVERT, `PANORAMA_GET_RAW_FILE`) is keyed only by output
  basename — changing conversion parameters does not invalidate it.
- **Shell:** `process.shell = bash -euo pipefail`. Most modules tee tool output to
  published `.stdout`/`.stderr` files via `> >(tee ...)` process substitution (with a
  trailing `echo` to flush). This pattern is **racy**: for a fast command that emits
  nothing, the async `tee` may not create the declared output file before Nextflow
  collects outputs — this broke `ADD_PARAMS_TO_MAGNUM_CONF` on NF26. For fast/quiet
  commands, redirect straight to the file (`2> x.stderr`) instead of teeing (this bit
  `ADD_PARAMS_TO_MAGNUM_CONF`, `FILTER_PIN_COLUMNS`, and `COMBINE_PIN_FILES` on NF26, now
  all fixed); reserve the tee pattern for slower tools where live streaming is useful and
  the race doesn't occur (see P5).
- **PIN format:** Magnum/Percolator PIN files list a PSM's extra proteins as
  additional **header-less, tab-separated columns** at the end of the row, so data
  rows can have more fields than the header. `FILTER_PIN_COLUMNS` slices only the
  columns before the trailing `Proteins` column and preserves the protein tail
  verbatim — preserve that invariant in any PIN-touching code.
- **Nextflow version & strict config language.** Floor is `!>=25.10.0` (manifest);
  CI and `test/run-tests.sh` validate against 25.10.x and 26.04.x. The strict config
  language (25.10+/26) forbids, in `*.config` files: function definitions, `if`
  statements, and `def` variable declarations. Consequences encoded in this repo:
  per-profile `process.resourceLimits` instead of a `check_max` function; secrets
  loaded as expressions (`env.X = ...getSecret("X")?.value`, no `if`); execution
  reports use static filenames + `overwrite = true` (no computed timestamp variable).
  Always run `nextflow lint` after editing any `.nf`/`.config` — it must stay
  error-free (the harness gates on it).
- **Dynamic process directives need closures.** A directive that references an input
  variable must be a closure, e.g. `publishDir { "${params.result_dir}/x/${sample_id}" }`.
  A bare GString (`publishDir "...${sample_id}"`) throws `No such variable` on
  Nextflow 26 because it is evaluated without task inputs in scope.
- **No `lib/` Groovy classes.** Autoloading of `lib/*.groovy` is gone in the new
  language; helper logic (e.g. the completion email) lives in `main.nf` functions, and
  `workflow.onComplete` is registered **inside** the entry `workflow {}` block.

## Testing

Two complementary layers. There is no `nf-test` harness (one may be added later;
`.claude/skills/nf-test` documents the conventions for when we do).

**1. `test/run-tests.sh` — Docker-free, multi-version (primary local gate).**
For each pinned Nextflow version (floor first) it runs:
- `nextflow lint` over all scripts, configs, and drivers — must be error-free.
- **Stub workflow runs** of `conf/test_combined.config` and `conf/test_separate.config`
  (3 input mzMLs, Docker disabled), asserting the expected per-sample published outputs
  exist — exercises wiring, mode branching, and per-sample fan-out. Plus a RAW→mzML
  branch run (placeholder `test/fixtures/raw/sample.raw`) that exercises the
  `from_raw_files`/`MSCONVERT` path that the mzML-based configs never reach.
- **Real `ADD_PARAMS_TO_MAGNUM_CONF`**: asserts both declared outputs exist — the
  substituted per-sample `.conf` and the `.stderr` file (the latter guards the
  process-substitution race that broke this process on NF26).
- **Real `FILTER_PIN_COLUMNS`** on `test/fixtures/multiprotein.pin`: asserts a feature
  column is removed while a PSM's multiple proteins survive, and that removing a
  non-existent column or the `Proteins` column exits non-zero.
- **Real `VALIDATE_DECOY_OPTIONS`** across its decoy-consistency matrix (two valid
  configs accepted, four invalid combinations rejected) using `test-data/` fixtures.

  These shell-only processes (`ADD_PARAMS_TO_MAGNUM_CONF`, `FILTER_PIN_COLUMNS`,
  `VALIDATE_DECOY_OPTIONS`) run on the host with no container; the drivers in
  `test/drivers/` `include` the real module and run it standalone.

**2. `.github/workflows/ci.yml`.** Two jobs, both `fail-fast: false`:
- **`harness`** — runs `test/run-tests.sh` as a matrix over Nextflow **25.10.4 and
  26.04.0 in parallel** (Docker-free; the launcher + engine are cached per version).
- **`smoke-tests`** — real toolchain (Magnum, Percolator, YARP, msconvert; needs
  Docker) over the `conf/smoke_*.config` matrix × **both Nextflow versions**: single vs
  multi mzML × pre-existing vs YARP-generated decoys × combined vs separate × one
  PIN-filter case. Limelight upload is disabled (no instance in CI).

**Still NOT covered** (see Open Issues): the Limelight XML-convert + upload path is
never run against real tools (T1); smoke tests assert completion, not output content
(T2); CI runs only on push to `main`, not on `pull_request` (T4).

Test data lives in `test-data/` (small FASTAs, trimmed mzMLs, two Magnum confs);
harness fixtures in `test/fixtures/`.

## Open Issues

Tracked findings. Severity: **High** (correctness/breakage), **Med** (latent
correctness or portability), **Low** (cleanup/docs). Keep this list honest — add
when found, move to Resolved when fixed.

### Open

| ID | Sev | Area | Description |
|----|-----|------|-------------|
| F2 | Med | caching | `storeDir` for MSCONVERT / `PANORAMA_GET_RAW_FILE` is keyed only by output basename: changing msconvert params won't invalidate the cache, and same-basename inputs from different sources collide. |
| F3 | Med | limelight | Combined mode passes the unmodified **template** `magnum_conf` (still `database = DO_NOT_CHANGE`) to Limelight XML conversion, while separate mode passes the per-sample resolved conf — recorded search metadata can differ between modes. |
| F4 | Med | limelight | `UPLOAD_TO_LIMELIGHT*` sets `--path="${workflow.launchDir}"` but passes scan files as basenames staged in the task workdir; the importer may not find them. Entirely untested (see T1). |
| T1 | Med | testing | The entire Limelight convert + upload path is never run against real tools (disabled in smoke, stubbed in CI) — F4 and C4 live in this blind spot. |
| C4 | Low | dead code | `UPLOAD_TO_LIMELIGHT_SEP` declares a `search_short_name` input it never uses (documented as "ignored in separate mode"). |
| P1 | Low | inputs | Inconsistent remote detection: `spectra_dir.contains("https://")` vs `fasta`/`magnum_conf` `.startsWith(...)`. A local path containing the substring would be misrouted. |
| P2 | Low | panorama | Panorama raw download relies on a trailing slash in the WebDAV URL (`${url}${name}`, unvalidated); only `.raw` files are ever enumerated. |
| P3 | Low | portability | MAGNUM uses GNU-specific `sed -i`/`\s`; relies on the magnum image shipping GNU sed. |
| P4 | Low | resources | `-Xmx${mem.toGiga()-1}G` underflows to 0/negative if any label ever assigns <2 GB (currently safe; smallest label is 8 GB). |
| P5 | Low | shell | The slow real-tool modules (Magnum, Percolator, Panorama, Limelight) still capture `.stdout`/`.stderr` via `> >(tee ...)` process substitution. This is intentional (live streaming to `.command.out/.err` during long runs) and does not race in practice — those tools run long enough for `tee` to create the files before output collection. Only fast/quiet commands need the synchronous-redirect treatment. |
| T2 | Low | testing | The real-tool **smoke** matrix asserts only that the run completes, not output counts/content. (The Docker-free harness now asserts published-output existence and real `FILTER_PIN_COLUMNS`/`VALIDATE_DECOY_OPTIONS` behavior.) |
| T4 | Low | ci | CI (`harness` + `smoke-tests` jobs) runs only on `push` to `main`; there is no `pull_request` trigger, so changes aren't gated before landing. The Docker-free `harness` job is the natural PR gate. |

### Resolved (kept for context — do not re-report)

| ID | Area | Fix |
|----|------|-----|
| B1 | aws | `VALIDATE_DECOY_OPTIONS` had no `container` (could not run on awsbatch) — added `container params.images.ubuntu` + `label 'process_low_constant'`. |
| B2 | jvm | `-Djava.aws.headless=true` typo in 5 Java-invoking modules — corrected to `java.awt.headless`. |
| F1 | filtering | `FILTER_PIN_COLUMNS` sliced rows by header column count and dropped a multi-protein PSM's extra proteins — rewritten to preserve the trailing protein tail; also now errors if asked to remove the `Proteins` column. |
| NF26 | compat | Nextflow 26 + strict-config migration: `check_max`→per-profile `process.resourceLimits` (removed `max_*` params from schema/configs/docs); dynamic `publishDir` GStrings→closures; secrets `if`-blocks→expression assignments; timestamped report files→static names + `overwrite`; `lib/EmailTemplate.groovy`+`assets/` inlined into a `main.nf` function with `onComplete` moved inside `workflow {}`; `aws.batch.*` client options→`aws.client`; manifest floor `!>=25.10.0`. Lint-clean and stub-passing on 25.10.x and 26.04.x via `test/run-tests.sh`. |
| C1 | dead code | Removed unused `magnum_conf_ch` from `main.nf`. |
| C2 | dead code | Removed unused `PANORAMA_GET_COMET_PARAMS` (import + process). |
| C3 | dead code | Removed leftover `workflow dummy`. |
| C5 | docs | Fixed `nextflow.config` header docstring (was "nf-maccoss-trex" / "data-ind…"). |
| D2 | docs | Fixed `docs/source/workflow_parameters.rst` example `quant_spectra_dir`→`spectra_dir`. |
| D1 | docs | README rewritten; removed the inaccurate hard-coded "Output" path section (output layout now lives in the readthedocs docs). |
| P5a | shell | Fast/quiet shell helpers dropped a declared `.stderr` output on NF26 — the async `>(tee ...)` hadn't created the file before output collection because the command (sed/awk/python) finished instantly. Fixed `ADD_PARAMS_TO_MAGNUM_CONF`, `FILTER_PIN_COLUMNS`, and `COMBINE_PIN_FILES` to redirect stderr synchronously (`2>`/`2>>`). The harness runs the real `ADD_PARAMS`/`FILTER` processes and asserts their `.stderr` (+ `.conf`/`.pin`) outputs. Slow-tool modules intentionally keep `tee` (P5). |
| T3 | testing | Multi-protein `FILTER_PIN_COLUMNS` behavior is now covered by `test/run-tests.sh` (real process on `test/fixtures/multiprotein.pin`, plus both error paths). |
