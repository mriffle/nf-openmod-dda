process MAGNUM {
    publishDir "${params.result_dir}/magnum/${sample_id}", failOnError: true, mode: 'copy'
    label 'process_high_constant'
    container params.images.magnum

    input:
        tuple val(sample_id), path(mzml_file), path(magnum_conf)
        path fasta_file

    output:
        tuple val(sample_id), path("*.pep.xml"), emit: pepxml
        tuple val(sample_id), path("*.perc.txt"), emit: pin
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr
        path("*.diag.xml"), emit: diagxml, optional: true

    script:
    """
    echo "Running magnum for ${sample_id}..."
    magnum ${magnum_conf} \
        > >(tee "${sample_id}.magnum.stdout") 2> >(tee "${sample_id}.magnum.stderr" >&2)

    echo "DONE!"
    """

    stub:
    """
    touch "${sample_id}.pep.xml"
    touch "${sample_id}.perc.txt"
    touch "${sample_id}.magnum.stdout"
    touch "${sample_id}.magnum.stderr"
    """
}
