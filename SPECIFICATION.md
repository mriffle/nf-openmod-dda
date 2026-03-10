# nf-openmod-dda Specification

## Purpose

`nf-openmod-dda` is a Nextflow DSL2 workflow for open-modification DDA proteomics analysis built around Magnum.

Its job is to automate the end-to-end execution path that typically includes:

- acquiring input files locally or from PanoramaWeb
- converting vendor RAW files to mzML when needed
- preparing Magnum configuration per sample
- validating or generating FASTA decoys
- running Magnum searches
- running Percolator for post-processing
- optionally converting results to Limelight XML and uploading them to Limelight

The project is intended to provide a reproducible, containerized workflow that can run locally, on Slurm, or on AWS Batch without requiring direct installation of each proteomics tool on the host.

## Problem Being Solved

Open-modification proteomics searches require multiple tools, format conversions, search configuration steps, and optional publication or sharing steps. Running these manually is error-prone and difficult to reproduce.

This workflow solves that by:

- standardizing the execution order
- encapsulating tool invocations in isolated processes
- using containers for tool version control
- supporting multiple execution environments
- preserving a consistent result layout
- handling both per-file and combined downstream analysis modes

## Scope and Design Intent

This repository is a workflow implementation, not a general proteomics library.

The main design goals are:

- clear orchestration of external command-line tools
- portability across execution backends
- minimal host dependencies beyond Nextflow and container support
- explicit process boundaries and result publishing
- straightforward extension when new workflow steps are added

## Source of Truth

When reasoning about this repository, use these files in order of importance:

1. `main.nf`
2. `workflows/*.nf`
3. `modules/*.nf`
4. `nextflow.config`
5. `nextflow_schema.json`
6. `conf/base.config`
7. `container_images.config`
8. `README.md` and `docs/source/*`

Generated runtime artifacts under `work/`, `reports/`, and `docs/build/` are not implementation source of truth.

## Parameter Schema Contract

Workflow parameters are validated with `nf-schema` using `nextflow_schema.json`.

Maintenance rule:

- Any change to workflow parameters (add/remove/rename/type/default/required behavior) must be reflected in `nextflow_schema.json` in the same change.
- Parameter changes should also stay consistent across `nextflow.config`, docs, and test configs.
- CI/stub tests should be run after schema-affecting changes to confirm validation still passes.

## High-Level Architecture

The workflow is organized into four layers.

### 1. Orchestration layer

`main.nf` is the top-level controller. It:

- resolves input locations
- chooses local vs Panorama retrieval paths
- chooses RAW vs mzML handling
- validates decoy configuration
- optionally generates decoys
- dispatches into one of two mode-specific subworkflows

### 2. Subworkflow layer

The `workflows/` directory defines the high-level execution strategies:

- `magnum_percolator_combined.nf`
- `magnum_percolator_separate.nf`

These two files define how Magnum outputs are fed into Percolator and Limelight handling.

### 3. Process/module layer

The `modules/` directory contains the concrete process wrappers for each program or helper task. Each module is responsible for one bounded operation such as search execution, format conversion, upload, or validation.

### 4. Runtime/config layer

Repository-wide runtime behavior is defined in:

- `nextflow.config` for params, executors, reporting, secrets, and profiles
- `conf/base.config` for label-based resource policies
- `container_images.config` for mapping logical tool names to container images

## Implementation Model

This project uses Nextflow DSL2 with included modules and subworkflows.

The common control pattern is:

1. build channels from user parameters
2. normalize input shape
3. transform data through process modules
4. publish outputs into a predictable results directory structure
5. emit trace, report, and timeline artifacts

Data is frequently carried as tuples keyed by sample base name so that downstream joins and mode-specific grouping remain explicit.

## Workflow Summary

The implemented workflow can be understood as the following conceptual path:

1. Resolve `fasta`, `magnum_conf`, and `spectra_dir`
2. If any supported input is remote, fetch it from PanoramaWeb
3. Validate decoy-related settings and FASTA state
4. If configured, generate decoys with YARP
5. If spectra are RAW, convert them to mzML
6. Create sample-specific Magnum configuration files
7. Run Magnum per sample
8. Optionally filter Percolator PIN columns before Percolator
9. Run Percolator either once on combined data or once per sample
10. If enabled, convert outputs to Limelight XML
11. If enabled, upload results to Limelight
12. Optionally send completion email

## Workflow Steps and Program Roles

The workflow is primarily an orchestrator around external programs.

### Panorama client

Used to list and download files from PanoramaWeb when inputs are specified as WebDAV URLs.

Role:

- remote file acquisition
- remote raw file enumeration
- remote raw file download

### msconvert

Used only when the spectra inputs are vendor RAW files.

Role:

- convert RAW to mzML prior to search

### VALIDATE_DECOY_OPTIONS

Shell-based validation step implemented as a process module.

Role:

- ensure the FASTA decoy content and Magnum decoy settings are consistent with pipeline parameters
- fail early on invalid decoy combinations

### YARP

Optional step for decoy generation.

Role:

- create a decoy-augmented FASTA when the workflow is configured to generate decoys itself

### ADD_PARAMS_TO_MAGNUM_CONF

Repository helper step that rewrites or patches the Magnum configuration for each sample.

Role:

- inject the actual FASTA path
- inject the actual mzML path
- produce a per-sample Magnum config used by the search step

### Magnum

Primary search engine in this workflow.

Role:

- perform the open modification search
- emit PepXML and Percolator input text output per sample

### COMBINE_PIN_FILES

Helper step used only in combined mode.

Role:

- merge multiple Percolator input files into a single combined input file

### FILTER_PIN_COLUMNS

Optional helper step used immediately before Percolator in both combined and separate mode.

Role:

- remove user-specified header columns from Percolator PIN input files
- preserve tab-delimited layout for the remaining columns

### Percolator

Post-processing and statistical scoring step.

Role:

- score Magnum search results
- emit Percolator XML output

### Limelight XML conversion

Optional downstream conversion step.

Role:

- convert Magnum and Percolator outputs into Limelight XML format

### Limelight upload

Optional publication step.

Role:

- submit Limelight XML, scan-file references, and metadata to a Limelight instance

### Email template

Auxiliary completion notification behavior.

Role:

- render an HTML completion email when email support is configured

## Modes of Operation

The workflow has several important branching dimensions.

### Local vs Panorama-backed inputs

If a supported path begins with `https://`, it is treated as a PanoramaWeb resource.

Implications:

- FASTA can be remote
- Magnum config can be remote
- spectra can be remote
- remote spectra retrieval is oriented around raw files, not remote mzML discovery

### RAW vs mzML spectra inputs

For local spectra directories:

- if `.mzML` files exist, they are used directly
- otherwise `.raw` files are used and converted with msconvert

This means mzML input bypasses conversion, while RAW input triggers conversion.

### Combined vs separate downstream processing

This is the most important workflow mode switch.

#### Combined mode

Selected when `process_separately = false`.

Characteristics:

- Magnum runs per sample
- all Percolator input files are collected and merged
- Percolator runs once on the merged data
- if Limelight is enabled, one combined Limelight XML is produced
- if Limelight upload is enabled, one combined upload is performed

Use this mode when combined statistical treatment is preferred.

#### Separate mode

Selected when `process_separately = true`.

Characteristics:

- Magnum runs per sample
- Percolator runs per sample
- Limelight XML is generated per sample
- Limelight upload is performed per sample

Use this mode when preserving independent per-file results is more important than pooling them for downstream scoring.

### Single-file vs multiple-file runs

There is no separate dedicated single-file code path.

Single-file execution is a natural special case of the same workflow:

- one spectra input still goes through the same normalization and sample-keying logic
- combined mode still works, but with only one sample contributing to downstream aggregation
- separate mode preserves the same per-sample semantics but the sample count is one

Multiple-file runs matter primarily for:

- whether msconvert runs multiple times
- whether Magnum runs multiple times
- whether Percolator consumes one combined input or multiple separate inputs
- whether Limelight output represents one combined search or multiple searches

## Channel and Data Shape Conventions

Important conventions for maintainers and coding agents:

- sample identity is usually derived from file basename
- many downstream joins depend on matching tuple keys
- combined mode intentionally collects channel outputs before Percolator and Limelight conversion
- separate mode intentionally preserves keyed tuples to maintain sample identity

When modifying the workflow, avoid changing tuple shapes casually. Mode-specific joins depend on them.

## Docker and Container Image Resolution

Container selection is intentionally indirect.

### How image selection works

1. `container_images.config` defines `params.images`, a map from logical tool names to image references.
2. Each process module declares `container params.images.<tool_key>`.
3. Nextflow uses that process-level container directive when running the task.

This means image choice is determined by:

- the module being executed
- the `container` directive in that module
- the image mapping configured in `container_images.config`

### Why this matters

This design keeps process logic separate from concrete image tags.

If a tool image must change, the normal place to update it is `container_images.config`, not the module body, unless the logical tool mapping itself is changing.

### Representative mapping pattern

The repository currently uses logical image keys such as:

- `msconvert`
- `magnum`
- `percolator`
- `panorama_client`
- `magnum_to_limelight`
- `limelight_submit`
- `combine_percolator_input`
- `yarp`
- `ubuntu`

## Resource Management

Resource behavior is label-driven.

### Base resource policy

`conf/base.config` defines common labels and their CPU, memory, and time policies, including retry behavior.

Examples of labels include:

- `process_low_constant`
- `process_low`
- `process_medium`
- `process_high`
- `process_high_constant`
- `process_high_memory`
- `process_long`
- `process_very_long`
- `error_retry`

### How resources are applied

Each process module assigns one or more labels.

This means resource management is controlled by:

- process labels in modules
- profile-specific maximums in `nextflow.config`
- the `check_max` helper that caps requested resources to configured limits

### Profiles and executors

The repository defines multiple execution profiles.

At a high level:

- `standard` is for local execution
- `aws` is for AWS Batch
- `slurm` is for Slurm-based execution

Profiles mainly change:

- executor type
- queue settings where relevant
- max CPU, memory, and wall time
- cache locations for mzML and Panorama downloads

### Caching

The workflow uses cache-like storage via `storeDir` for some expensive steps.

Important cached behaviors include:

- RAW to mzML conversion outputs
- Panorama raw downloads

This reduces repeat work across runs when inputs and cache locations are stable.

## Secrets and External Service Integration

The workflow integrates with external services through Nextflow secrets and environment variables.

Important service areas:

- Limelight upload credentials
- Panorama API credentials

These secrets are loaded in `nextflow.config` and exposed to relevant processes through environment variables.

When modifying external-service behavior, treat credential handling as part of the runtime model, not as ordinary workflow input.

## Output Model

Results are published into a stable directory tree rooted under the configured result directory.

The general structure is organized by tool or stage, such as:

- `magnum/`
- `percolator/`
- `limelight/`
- `panorama/`
- `yarp/`

Reports and execution telemetry are emitted separately under the configured report directory.

The important design point is that `publishDir` is the user-facing result surface, while `work/` is task-execution internals.

## Testing Strategy

Testing in this repository is lightweight and currently centered on workflow wiring rather than full scientific validation.

### Stub-based tests

Most modules provide a `stub` section so the workflow can be exercised without running the full underlying tools.

This is useful for validating:

- control flow
- channel wiring
- process invocation structure
- mode branching

It is not sufficient to validate scientific correctness of the external tools.

### Test configs

The repository contains dedicated test configs for at least:

- combined mode
- separate mode

These are intended to exercise the two major downstream execution shapes.

## Continuous Integration

CI is implemented through GitHub Actions.

The current CI model is high level:

- install Java and Nextflow
- seed placeholder secrets needed by the workflow startup path
- run the workflow in stub mode using the combined test config
- run the workflow in stub mode using the separate test config

This means CI primarily verifies:

- the workflow parses and launches
- module inclusion works
- major branches still connect correctly

CI does not currently serve as a full integration or scientific-validation environment.

## Documentation Layout

User-facing documentation is split between:

- `README.md` for quick-start and repository summary
- `docs/source/*` for fuller narrative documentation

For implementation work, the docs are secondary to the workflow code and config.

## Guidance for Coding Agents

An agent working on this repository should keep these principles in mind.

### Prefer the existing structure

New workflow behavior should usually fit into one of these places:

- top-level routing in `main.nf`
- mode-specific orchestration in `workflows/`
- tool wrappers or helper steps in `modules/`
- runtime policy in config files

### Preserve mode semantics

Changes should not accidentally collapse the distinction between combined and separate mode.

In particular, be careful with:

- tuple key shapes
- `.collect()` behavior
- `.join()` behavior
- sample identity propagation

### Keep image and resource policy decoupled from process logic

If a change only updates image tags or resource ceilings, prefer changing config rather than module logic.

### Avoid overfitting this specification

This file is a high-level map, not a substitute for reading the exact modules involved in a change.

An agent should use this document to understand where to look and what architectural rules matter, then inspect the relevant code paths directly.

## What To Update When Features Change

When a new step, mode, integration, or execution rule is added, update this document if the change affects any of the following:

- high-level workflow order
- supported operating modes
- external systems or secrets
- resource-management model
- image-selection model
- testing or CI behavior
- source-of-truth file layout
- workflow parameter schema (`nextflow_schema.json`)

This document should remain concise, architectural, and stable. It should describe how the repository works without reproducing low-level code that can be inspected directly.
