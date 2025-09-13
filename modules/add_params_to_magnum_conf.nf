process ADD_PARAMS_TO_MAGNUM_CONF {
    publishDir "${params.result_dir}/magnum", failOnError: true, mode: 'copy', pattern: '*.stderr'
    publishDir "${params.result_dir}/magnum", failOnError: true, mode: 'copy', pattern: '*.conf'
    label 'process_low_constant'
    container params.images.ubuntu

    input:
        path magnum_conf
        path fasta
        path mzml_file


    output:
        tuple path(mzml_file), path("magnum_fixed.conf"), emit: magnum_job_tuple
        path("*.stderr"), emit: stderr

    script:

    """
    echo "Adding FASTA and mzML to magnum conf..."

    sed -e 's/database = \\S\\+/database = $fasta/g' $magnum_conf >magnum_tmp.conf 2> >(tee add-params-to-conf.stderr >&2)
    sed -e 's/MS_data_file = \\S\\+/MS_data_file = $mzml_file/g' magnum_tmp.conf >magnum_fixed.conf 2>> >(tee add-params-to-conf.stderr >&2)

    echo "DONE!" # Needed for proper exit
    """

    stub:
    """
    touch "magnum_fixed.conf"
    touch "add-params-to-conf.stderr"
    """
}