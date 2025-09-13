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
    python3 /usr/local/bin/combine-percolator-input-files.py \
    ${pin_files} \
    >combined.filtered.pin 2>> >(tee combine-pin.stderr >&2)
    echo "Done!" # Needed for proper exit
    """

    stub:
    """
    touch "combined.filtered.pin"
    touch "combine-pin.stderr"
    """
}