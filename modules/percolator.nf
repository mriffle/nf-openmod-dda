process PERCOLATOR {
    publishDir "${params.result_dir}/percolator", failOnError: true, mode: 'copy'
    label 'process_medium'
    label 'process_high_memory'
    container 'quay.io/protio/percolator:3.05'

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
        >percolator.stdout 2>percolator.stderr
    echo "Done!" # Needed for proper exit
    """

    stub:
    """
    touch "${pin_file.baseName}.pout.xml"
    """
}
