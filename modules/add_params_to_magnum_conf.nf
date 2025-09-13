process ADD_PARAMS_TO_MAGNUM_CONF {
    publishDir "${params.result_dir}/magnum/${sample_id}", failOnError: true, mode: 'copy', pattern: '*.stderr'
    publishDir "${params.result_dir}/magnum/${sample_id}", failOnError: true, mode: 'copy', pattern: '*.conf'
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

    sed -e "s|database = .*|database = ${fasta}|" ${magnum_conf} > magnum_tmp.conf 2> >(tee ${sample_id}.add-params.stderr >&2)
    sed -e "s|MS_data_file = .*|MS_data_file = ${mzml_file}|" magnum_tmp.conf > ${sample_id}.conf 2>> >(tee ${sample_id}.add-params.stderr >&2)

    echo "DONE!"
    """

    stub:
    """
    touch "${sample_id}.conf"
    touch "${sample_id}.add-params.stderr"
    """
}