#!/usr/bin/env nextflow

// Test driver: runs the real FILTER_PIN_COLUMNS process (not its stub) on a
// supplied PIN file so its awk logic can be exercised without Docker.
//
// Params:
//   --test_pin   path to an input PIN file
//   --test_cols  comma-delimited column names to remove (may be empty)

nextflow.enable.dsl = 2

include { FILTER_PIN_COLUMNS } from '../../modules/filter_pin_columns'

workflow {
    def raw  = (params.test_cols ?: '').toString()
    def cols = raw ? raw.split(',').collect { c -> c.trim() }.findAll { c -> c } : []

    FILTER_PIN_COLUMNS(
        channel.of( tuple('sample', file(params.test_pin)) ),
        cols
    )
}
