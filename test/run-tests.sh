#!/usr/bin/env bash
#
# Self-contained test harness for nf-openmod-dda.
#
# Runs, for each pinned Nextflow version, with NO dependency on Docker:
#   1. `nextflow lint` over all scripts and configs (must be error-free)
#   2. stub workflow runs of combined and separate mode (wiring / fan-out /
#      per-sample publish layout)
#   3. the real FILTER_PIN_COLUMNS process on a multi-protein PIN, plus its two
#      error paths (run on the host via a tiny driver, no container)
#   4. the real VALIDATE_DECOY_OPTIONS process across its pass/fail cases
#
# The Nextflow launcher and each engine version are downloaded into a local,
# git-ignored directory (test/.nextflow-dist) and all run artifacts land in
# test/.work, so nothing pollutes the repository root.
#
# Usage:
#   test/run-tests.sh
#   NXF_TEST_VERSIONS="25.10.4 26.04.0" test/run-tests.sh   # override versions
#
# Requirements: bash, curl, java (for Nextflow), and standard coreutils/awk.

set -uo pipefail

# --- locations (resolved relative to this script, so it is portable) ---------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$SCRIPT_DIR/.nextflow-dist"
WORK_DIR="$SCRIPT_DIR/.work"
HARNESS_CONFIG="$SCRIPT_DIR/harness.config"
LAUNCHER="$DIST_DIR/bin/nextflow"

export NXF_HOME="$DIST_DIR/home"          # engines + secrets live here (local)
export NXF_OFFLINE="${NXF_OFFLINE:-false}"
export CAPSULE_LOG=none

# Nextflow versions to test. First entry is the supported floor.
read -r -a VERSIONS <<< "${NXF_TEST_VERSIONS:-25.10.4 26.04.0}"

# --- reporting ---------------------------------------------------------------
if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; B=$'\033[1m'; Z=$'\033[0m'; else G=; R=; B=; Z=; fi
PASS=0; FAIL=0; FAILURES=()
V="(setup)"

ok()   { PASS=$((PASS+1)); printf '  %sPASS%s %s\n' "$G" "$Z" "$1"; }
fail() {
    FAIL=$((FAIL+1)); FAILURES+=("[$V] $1")
    printf '  %sFAIL%s %s\n' "$R" "$Z" "$1"
    [ -n "${2:-}" ] && [ -f "$2" ] && tail -n 15 "$2" | sed 's/^/        | /'
    return 0
}
section() { printf '\n%s==== %s ====%s\n' "$B" "$1" "$Z"; }

# --- provisioning ------------------------------------------------------------
bootstrap_launcher() {
    [ -x "$LAUNCHER" ] && return 0
    section "Bootstrapping Nextflow launcher into $DIST_DIR/bin"
    mkdir -p "$DIST_DIR/bin" "$NXF_HOME" "$WORK_DIR"
    ( cd "$DIST_DIR/bin" && curl -fsSL https://get.nextflow.io | bash ) \
        || { echo "ERROR: failed to download the Nextflow launcher"; exit 1; }
    chmod +x "$LAUNCHER"
}

provision_engine() { # $1 = version
    ( cd "$WORK_DIR" && NXF_VER="$1" "$LAUNCHER" -version ) >/dev/null 2>&1
}

seed_secrets() {
    # Placeholder secrets so the config's secret loader does not warn; the stub
    # tests never use their values.
    ( cd "$WORK_DIR" && NXF_VER="${VERSIONS[0]}" "$LAUNCHER" secrets set PANORAMA_API_KEY PLACEHOLDER ) >/dev/null 2>&1 || true
    ( cd "$WORK_DIR" && NXF_VER="${VERSIONS[0]}" "$LAUNCHER" secrets set LIMELIGHT_SUBMIT_UPLOAD_KEY PLACEHOLDER ) >/dev/null 2>&1 || true
}

# --- tests -------------------------------------------------------------------
test_lint() {
    local log="$WORK_DIR/$V/lint.out"
    if ( cd "$WORK_DIR" && NXF_VER="$V" "$LAUNCHER" lint -o concise \
            "$REPO_ROOT/main.nf" "$REPO_ROOT/workflows" "$REPO_ROOT/modules" \
            "$REPO_ROOT/nextflow.config" "$REPO_ROOT/conf" "$REPO_ROOT/container_images.config" \
            "$REPO_ROOT/test/drivers" ) > "$log" 2>&1; then
        ok "lint (all scripts + configs error-free)"
    else
        fail "lint reported errors" "$log"
    fi
}

test_workflow_stub() { # $1 = config; rest = expected published files (under results/)
    local cfg="$1"; shift
    local ld="$WORK_DIR/$V/stub_${cfg%.config}"
    rm -rf "$ld"; mkdir -p "$ld"
    ln -s "$REPO_ROOT/test-data" "$ld/test-data"
    ln -s "$REPO_ROOT/example_files" "$ld/example_files"
    if ( cd "$ld" && NXF_VER="$V" "$LAUNCHER" -log "$ld/nf.log" run "$REPO_ROOT/main.nf" \
            -profile standard -stub -c "$REPO_ROOT/conf/$cfg" -c "$HARNESS_CONFIG" \
            -work-dir "$ld/work" --result_dir "$ld/results" --report_dir "$ld/reports" \
            ) > "$ld/out.txt" 2>&1; then
        local missing=0 f
        for f in "$@"; do
            [ -e "$ld/results/$f" ] || { missing=1; printf '        | missing expected output: results/%s\n' "$f"; }
        done
        if [ "$missing" -eq 0 ]; then ok "stub workflow: $cfg"; else fail "stub workflow: $cfg (missing outputs)" "$ld/out.txt"; fi
    else
        fail "stub workflow: $cfg (run failed)" "$ld/out.txt"
    fi
}

test_workflow_stub_raw() {
    # Exercise the RAW->mzML branch (from_raw_files=true / MSCONVERT inclusion) by
    # pointing spectra_dir at a dir with a placeholder .raw and no mzML. In stub mode
    # MSCONVERT just touches the .mzML, so an empty .raw is sufficient for wiring.
    local ld="$WORK_DIR/$V/stub_raw_branch"
    rm -rf "$ld"; mkdir -p "$ld"
    ln -s "$REPO_ROOT/test-data" "$ld/test-data"
    ln -s "$REPO_ROOT/example_files" "$ld/example_files"
    if ( cd "$ld" && NXF_VER="$V" "$LAUNCHER" -log "$ld/nf.log" run "$REPO_ROOT/main.nf" \
            -profile standard -stub -c "$REPO_ROOT/conf/test_combined.config" -c "$HARNESS_CONFIG" \
            --spectra_dir "$REPO_ROOT/test/fixtures/raw" \
            -work-dir "$ld/work" --result_dir "$ld/results" --report_dir "$ld/reports" \
            ) > "$ld/out.txt" 2>&1; then
        if [ -e "$ld/results/magnum/sample/sample.pep.xml" ]; then
            ok "stub workflow: RAW->mzML branch (msconvert)"
        else
            fail "stub workflow: RAW branch produced no magnum output" "$ld/out.txt"
        fi
    else
        fail "stub workflow: RAW branch (run failed)" "$ld/out.txt"
    fi
}

test_add_params() {
    # Real ADD_PARAMS_TO_MAGNUM_CONF: confirms both declared outputs are produced —
    # the per-sample .conf with substituted paths, and the .stderr file (which a
    # `>(tee ...)` process substitution could fail to create for these instant seds).
    local ld="$WORK_DIR/$V/add_params"
    rm -rf "$ld"; mkdir -p "$ld"
    if ( cd "$ld" && NXF_VER="$V" "$LAUNCHER" -log "$ld/nf.log" run "$REPO_ROOT/test/drivers/add_params_driver.nf" \
            -c "$REPO_ROOT/container_images.config" -c "$HARNESS_CONFIG" \
            -work-dir "$ld/work" --result_dir "$ld/results" \
            --test_mzml "$REPO_ROOT/test-data/test1.mzML" \
            --test_conf "$REPO_ROOT/test-data/Magnum-no-generate-decoys.conf" \
            --test_fasta "$REPO_ROOT/test-data/test.fasta" \
            ) > "$ld/out.txt" 2>&1; then
        local d="$ld/results/magnum/sample"
        if [ ! -f "$d/sample.add-params.stderr" ]; then
            fail "add_params: .stderr output not produced" "$ld/out.txt"; return; fi
        if ! grep -q '^database = test.fasta' "$d/sample.conf" 2>/dev/null \
           || ! grep -q '^MS_data_file = test1.mzML' "$d/sample.conf" 2>/dev/null; then
            fail "add_params: conf substitutions missing" "$d/sample.conf"; return; fi
        ok "add_params: produces .conf (substituted) and .stderr"
    else
        fail "add_params: run failed" "$ld/out.txt"
    fi
}

test_filter_preserves_proteins() {
    local ld="$WORK_DIR/$V/filter_happy"
    rm -rf "$ld"; mkdir -p "$ld"
    if ( cd "$ld" && NXF_VER="$V" "$LAUNCHER" -log "$ld/nf.log" run "$REPO_ROOT/test/drivers/filter_pin_columns_driver.nf" \
            -c "$REPO_ROOT/container_images.config" -c "$HARNESS_CONFIG" \
            -work-dir "$ld/work" --result_dir "$ld/results" \
            --test_pin "$REPO_ROOT/test/fixtures/multiprotein.pin" --test_cols 'Mass' \
            ) > "$ld/out.txt" 2>&1; then
        local out="$ld/results/percolator/sample/sample.columns_filtered.pin"
        if [ ! -f "$out" ]; then fail "filter: output not produced" "$ld/out.txt"; return; fi
        # 'Mass' must be gone from the header
        if head -n1 "$out" | tr '\t' '\n' | grep -qx 'Mass'; then
            fail "filter: removed column 'Mass' still present" "$out"; return; fi
        # multi-protein PSM must keep ALL proteins (psm2: 6 head cols + 3 proteins = 9 fields)
        local nf2; nf2=$(awk -F'\t' '$1=="psm2"{print NF}' "$out")
        if [ "$nf2" != "9" ] || ! grep -q 'sp|P3|C' "$out"; then
            fail "filter: multi-protein tail not preserved (psm2 NF=$nf2, want 9)" "$out"; return; fi
        ok "filter: removes column, preserves multi-protein tail"
    else
        fail "filter: happy-path run failed" "$ld/out.txt"
    fi
}

test_filter_rejects() { # $1 = column name that should cause a non-zero exit
    local col="$1"
    local ld="$WORK_DIR/$V/filter_reject_$col"
    rm -rf "$ld"; mkdir -p "$ld"
    ( cd "$ld" && NXF_VER="$V" "$LAUNCHER" -log "$ld/nf.log" run "$REPO_ROOT/test/drivers/filter_pin_columns_driver.nf" \
        -c "$REPO_ROOT/container_images.config" -c "$HARNESS_CONFIG" \
        -work-dir "$ld/work" --result_dir "$ld/results" \
        --test_pin "$REPO_ROOT/test/fixtures/multiprotein.pin" --test_cols "$col" \
        ) > "$ld/out.txt" 2>&1
    if [ $? -ne 0 ]; then ok "filter: rejects '$col' (non-zero exit)"; else fail "filter: '$col' should have failed but succeeded" "$ld/out.txt"; fi
}

test_validate() { # $1=name $2=fasta $3=conf $4=generate_decoys $5=pass|fail
    local name="$1" fasta="$2" conf="$3" gen="$4" expect="$5"
    local ld="$WORK_DIR/$V/validate_$name"
    rm -rf "$ld"; mkdir -p "$ld"
    ( cd "$ld" && NXF_VER="$V" "$LAUNCHER" -log "$ld/nf.log" run "$REPO_ROOT/test/drivers/validate_decoy_options_driver.nf" \
        -c "$REPO_ROOT/container_images.config" -c "$HARNESS_CONFIG" \
        -work-dir "$ld/work" \
        --test_fasta "$REPO_ROOT/$fasta" --test_conf "$REPO_ROOT/$conf" --test_generate_decoys "$gen" \
        ) > "$ld/out.txt" 2>&1
    local rc=$?
    if [ "$expect" = pass ]; then
        [ $rc -eq 0 ] && ok "validate: $name (accepts valid config)" || fail "validate: $name expected pass, got exit $rc" "$ld/out.txt"
    else
        [ $rc -ne 0 ] && ok "validate: $name (rejects invalid config)" || fail "validate: $name expected fail, but passed" "$ld/out.txt"
    fi
}

# --- main --------------------------------------------------------------------
bootstrap_launcher
seed_secrets

for V in "${VERSIONS[@]}"; do
    section "Nextflow $V"
    mkdir -p "$WORK_DIR/$V"
    if ! provision_engine "$V"; then
        fail "could not provision Nextflow $V"
        continue
    fi

    test_lint

    # Wiring + per-sample publish layout (3 input mzMLs exercise fan-out).
    test_workflow_stub test_combined.config \
        magnum/test1/test1.pep.xml magnum/test3/test3.perc.txt \
        percolator/combined/combined.pout.xml limelight/results.limelight.xml
    test_workflow_stub test_separate.config \
        magnum/test2/test2.pep.xml percolator/test1/test1.pout.xml \
        percolator/test3/test3.pout.xml limelight/test2/test2.limelight.xml
    test_workflow_stub_raw

    # ADD_PARAMS_TO_MAGNUM_CONF real script + declared outputs (real sed, no Docker).
    test_add_params

    # FILTER_PIN_COLUMNS correctness + failure points (real awk, no Docker).
    test_filter_preserves_proteins
    test_filter_rejects NoSuchColumn
    test_filter_rejects Proteins

    # VALIDATE_DECOY_OPTIONS decoy-consistency matrix (real shell, no Docker).
    test_validate ok_existing_decoys   test-data/test-decoys.fasta test-data/Magnum-no-generate-decoys.conf false pass
    test_validate ok_magnum_generates  test-data/test.fasta        test-data/Magnum.conf                    false pass
    test_validate err_missing_decoys   test-data/test.fasta        test-data/Magnum-no-generate-decoys.conf false fail
    test_validate err_decoys_with_yarp test-data/test-decoys.fasta test-data/Magnum-no-generate-decoys.conf true  fail
    test_validate err_both_generate    test-data/test.fasta        test-data/Magnum.conf                    true  fail
    test_validate err_magnum_on_decoys test-data/test-decoys.fasta test-data/Magnum.conf                    false fail
done

# --- summary -----------------------------------------------------------------
section "Summary"
printf '%s%d passed, %d failed%s (Nextflow versions: %s)\n' "$B" "$PASS" "$FAIL" "$Z" "${VERSIONS[*]}"
if [ "$FAIL" -gt 0 ]; then
    printf '\nFailures:\n'
    for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
    exit 1
fi
echo "All tests passed."
