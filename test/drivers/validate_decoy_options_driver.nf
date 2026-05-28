#!/usr/bin/env nextflow

// Test driver: runs the real VALIDATE_DECOY_OPTIONS process (not its stub) so
// its decoy-consistency checks can be exercised without Docker. The process
// exits non-zero on an invalid decoy configuration.
//
// Params:
//   --test_fasta            path to a FASTA file
//   --test_conf             path to a Magnum config file
//   --test_generate_decoys  true|false (pipeline generate_decoys setting)

nextflow.enable.dsl = 2

include { VALIDATE_DECOY_OPTIONS } from '../../modules/validate_decoy_options'

workflow {
    VALIDATE_DECOY_OPTIONS(
        file(params.test_fasta),
        file(params.test_conf),
        params.test_generate_decoys
    )
}
