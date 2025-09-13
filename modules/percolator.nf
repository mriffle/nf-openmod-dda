process PERCOLATOR {
    publishDir "${params.result_dir}/percolator/${sample_id}", failOnError: true, mode: 'copy'
    label 'process_medium'
    label 'process_high_memory'
    container params.images.percolator

    input:
        tuple val(sample_id), path(pin_file)

    output:
        tuple val(sample_id), path("${sample_id}.pout.xml"), emit: pout
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
    """
    echo "Running percolator for ${sample_id}..."
    percolator \
        -X "${sample_id}.pout.xml" \
        ${pin_file} \
        > >(tee "${sample_id}.percolator.stdout") 2> >(tee "${sample_id}.percolator.stderr" >&2)
    
    echo "Done!"
    """

    stub:
    """
    touch "${sample_id}.pout.xml"
    touch "${sample_id}.percolator.stdout"
    touch "${sample_id}.percolator.stderr"
    """
}
