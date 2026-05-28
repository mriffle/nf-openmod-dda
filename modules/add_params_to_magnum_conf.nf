process ADD_PARAMS_TO_MAGNUM_CONF {
    publishDir { "${params.result_dir}/magnum/${sample_id}" }, failOnError: true, mode: 'copy', pattern: '*.stderr'
    publishDir { "${params.result_dir}/magnum/${sample_id}" }, failOnError: true, mode: 'copy', pattern: '*.conf'
    label 'process_low_constant'
    container params.images.ubuntu

    input:
        tuple val(sample_id), path(mzml_file)
        path magnum_conf
        path fasta


    output:
        tuple val(sample_id), path(mzml_file), path("${sample_id}.conf"), emit: magnum_job_tuple
        path("*.stderr"), emit: stderr

    script:

    """
    echo "Adding FASTA and mzML to magnum conf..."

    # Redirect stderr straight to the file (created synchronously by the shell)
    # rather than via a `>(tee ...)` process substitution: these seds are
    # instantaneous and emit no stderr, and the async tee could otherwise fail to
    # create the declared `*.stderr` output before Nextflow collects it.
    sed -e "s|database = .*|database = ${fasta}|" ${magnum_conf} > magnum_tmp.conf 2> ${sample_id}.add-params.stderr
    sed -e "s|MS_data_file = .*|MS_data_file = ${mzml_file}|" magnum_tmp.conf > ${sample_id}.conf 2>> ${sample_id}.add-params.stderr

    echo "DONE!"
    """

    stub:
    """
    touch "${sample_id}.conf"
    touch "${sample_id}.add-params.stderr"
    """
}