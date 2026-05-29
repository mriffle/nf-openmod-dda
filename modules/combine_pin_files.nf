process COMBINE_PIN_FILES {
    publishDir "${params.result_dir}/percolator", failOnError: true, mode: 'copy'
    label 'process_low_constant'
    container params.images.combine_percolator_input

    input:
        path pin_files

    output:
        path("combined.filtered.pin"), emit: combined_pin
        path("*.stderr"), emit: stderr

    script:
    """
    echo "Combining percolator input files..."
    # Redirect stderr straight to the declared output file (created synchronously)
    # rather than via an async `>(tee ...)` process substitution, which can fail to
    # create the file before Nextflow collects outputs when the command is fast.
    python3 /usr/local/bin/combine-percolator-input-files.py \
    ${pin_files} \
    >combined.filtered.pin 2> combine-pin.stderr
    echo "Done!" # Needed for proper exit
    """

    stub:
    """
    touch "combined.filtered.pin"
    touch "combine-pin.stderr"
    """
}