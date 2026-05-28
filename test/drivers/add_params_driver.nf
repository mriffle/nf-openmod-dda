#!/usr/bin/env nextflow

// Test driver: runs the real ADD_PARAMS_TO_MAGNUM_CONF process (not its stub) so its
// sed/redirection logic and declared outputs (the per-sample .conf and the .stderr
// file) are exercised without Docker.
//
// Params:
//   --test_mzml   path to a stand-in mzML file (only its name is used)
//   --test_conf   path to a Magnum config template
//   --test_fasta  path to a stand-in FASTA file (only its name is used)

nextflow.enable.dsl = 2

include { ADD_PARAMS_TO_MAGNUM_CONF } from '../../modules/add_params_to_magnum_conf'

workflow {
    ADD_PARAMS_TO_MAGNUM_CONF(
        channel.of( tuple('sample', file(params.test_mzml)) ),
        file(params.test_conf),
        file(params.test_fasta)
    )
}
