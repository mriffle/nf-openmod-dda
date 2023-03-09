process COMBINE_PIN_FILES {
    publishDir "${params.result_dir}/percolator", failOnError: true, mode: 'copy'
    label 'process_low_constant'
    container "quay.io/protio/combine-percolator-input-files:1.0.0"

    input:
        path pin_files

    output:
        path("combined.filtered.pin"), emit: combined_pin
        path("*.stderr"), emit: stderr

    script:
    """
    echo "Combining percolator input files..."
    python3 combine-percolator-input-files.py ${pin_files} \
    >combined.filtered.pin 2>>combine-pin.stderr
    echo "Done!" # Needed for proper exit
    """
}