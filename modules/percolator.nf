process PERCOLATOR {
    publishDir "${params.result_dir}/percolator", failOnError: true, mode: 'copy'
    label 'process_medium'
    label 'process_high_memory'
    container params.images.percolator

    input:
        path pin_file

    output:
        path("${pin_file.baseName}.pout.xml"), emit: pout
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
    """
    echo "Running percolator..."
    percolator \
        -X "${pin_file.baseName}.pout.xml" \
        ${pin_file} \
        > >(tee "percolator.stdout") 2> >(tee "percolator.stderr" >&2)
    echo "Done!" # Needed for proper exit
    """

    stub:
    """
    touch "${pin_file.baseName}.pout.xml"
    touch "percolator.stdout"
    touch "percolator.stderr"
    """
}
