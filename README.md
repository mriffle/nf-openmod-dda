# nf-openmod-dda

A [Nextflow](https://www.nextflow.io/) workflow for **open-modification DDA proteomics**.
It runs a [Magnum](https://magnum-ms.org/) open-modification search, scores the results
with [Percolator](http://percolator.ms/), and optionally publishes them to
[Limelight](https://limelight-ms.org/) for visualization, sharing, and analysis.

📖 **Full documentation: <https://nf-openmod-dda.readthedocs.io/>**

## What it is

Open-modification searching, format conversion, decoy handling, and result publishing
normally involve several tools run by hand, which is error-prone and hard to reproduce.
This workflow wraps that whole path so it runs the same way every time. Given a FASTA
database, a Magnum configuration file, and a directory of spectra (mzML or vendor RAW),
it will:

1. Acquire inputs — locally or from [PanoramaWeb](https://panoramaweb.org/) (any path beginning with `https://`).
2. Validate decoy settings, and optionally generate decoys with [YARP](https://github.com/mriffle/yarp).
3. Convert vendor RAW files to mzML with [msconvert](https://proteowizard.sourceforge.io/) (only when needed).
4. Run **Magnum** on each spectra file.
5. Score with **Percolator** — either once over the combined results, or once per file.
6. Optionally convert to **Limelight XML** and upload it to a Limelight server.

Every step runs in a container, so the only host requirements are Nextflow and Docker.
The same workflow runs locally, on Slurm, or on AWS Batch by selecting an execution profile.

## Running it

You need [Nextflow](https://www.nextflow.io/) (25.10 or newer) and Docker. The simplest
start is a config file — see [`resources/pipeline.config`](resources/pipeline.config) for a
fully-commented example:

```bash
nextflow run mriffle/nf-openmod-dda -r main -profile standard -c pipeline.config
```

At minimum you set `fasta`, `spectra_dir`, and `magnum_conf`. The `standard` profile runs
locally; `slurm` and `aws` are also provided. Reading from PanoramaWeb or uploading to
Limelight requires credentials stored as Nextflow secrets.

**For the full parameter reference, profiles, secrets, and output layout, see the
[documentation](https://nf-openmod-dda.readthedocs.io/).**

## For the technically curious

### Architecture

The code is layered, most-authoritative first:

- **`main.nf`** — top-level routing: resolves inputs (local vs PanoramaWeb), validates
  decoys, optionally generates them, then dispatches to one of two subworkflows.
- **`workflows/*.nf`** — the two processing strategies (combined vs separate; see below).
- **`modules/*.nf`** — one process per bounded operation (Magnum, Percolator, msconvert,
  YARP, Limelight convert/upload, the Panorama client, the PIN helpers, decoy validation).
- **config layer** — `nextflow.config` (params, profiles, secrets, reports),
  `conf/base.config` (label-based resource policy), `container_images.config`
  (tool → image map), and `nextflow_schema.json` (parameter validation via
  [nf-schema](https://nextflow-io.github.io/nf-schema/)).

### Combined vs separate

The central mode switch is `process_separately`:

- **Combined** (default): Magnum runs per file, all Percolator-input (PIN) files are
  merged, and Percolator + Limelight run **once** over the pooled data — better joint statistics.
- **Separate**: per-file identity is preserved end to end via keyed tuples, so Percolator
  and Limelight run **per file** — easier to compare individual runs.

### Patterns

- **Containers are indirection.** Each module declares `container params.images.<tool>`;
  concrete image tags live only in `container_images.config`.
- **Resources are label-driven.** Processes carry labels (`process_low`, `process_high_memory`, …)
  defined in `conf/base.config`; each profile sets `process.resourceLimits` to clamp requests
  to the executor's real ceiling.
- **Data flows as `tuple(sample_id, …)`** keyed on file basename; the mode-specific joins
  depend on those keys.
- **`https://` means PanoramaWeb.** Any input path starting with `https://` is treated as a
  PanoramaWeb WebDAV URL; results are published under the configured `result_dir`, organized
  by tool/stage.

The workflow targets Nextflow's strict configuration/script language, is kept error-free
under `nextflow lint`, and is validated against Nextflow 25.10 and 26.04.

### Testing

- **`test/run-tests.sh`** is a self-contained, Docker-free harness. It downloads the
  Nextflow launcher and each pinned engine into a local directory, then runs — for every
  supported version — `nextflow lint`, stub runs of both modes (wiring and per-sample
  fan-out), and the real shell-based steps: `FILTER_PIN_COLUMNS` (multi-protein handling
  plus its error paths) and `VALIDATE_DECOY_OPTIONS` (its accept/reject matrix).

  ```bash
  test/run-tests.sh                                      # all pinned versions
  NXF_TEST_VERSIONS="25.10.4 26.04.0" test/run-tests.sh  # override versions
  ```

- **GitHub Actions** runs that harness across Nextflow 25.10 and 26.04 in parallel, plus a
  Docker-based **smoke matrix** that exercises the real toolchain (Magnum, Percolator, YARP,
  msconvert) end to end on small committed test data in `test-data/`.

## License

See [LICENSE](LICENSE).
