process YARP {
    publishDir "${params.result_dir}/yarp/${sample_id}", failOnError: true, mode: 'copy'
    label 'process_low'
    label 'error_retry'
    container params.images.yarp

    input:
        path fasta_file

    output:
        path("${fasta_file.baseName}.plus-decoys.fasta"), emit: fasta_decoys

    script:

    """
    echo "Using YARP to add decoys to ${fasta_file}..."
    yarp \
    --fasta-file ${fasta_file} \
    --decoy-method reverse \
    --decoy-prefix DECOY_ \
    >${fasta_file.baseName}.plus-decoys.fasta 2>> >(tee yarp.stderr >&2)
    echo "Done!" # Needed for proper exit
    """

    stub:
    """
    touch ${fasta_file.baseName}.plus-decoys.fasta
    """
}
