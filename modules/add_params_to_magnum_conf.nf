process ADD_PARAMS_TO_MAGNUM_CONF {
    publishDir "${params.result_dir}/magnum", failOnError: true, mode: 'copy', pattern: '*[!.mzML]'
    label 'process_low_constant'
    container "${workflow.profile == 'aws' ? 'public.ecr.aws/docker/library/ubuntu:22.04' : 'ubuntu:22.04'}"

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

    sed -e 's/database = \\S\\+/database = $fasta/g' $magnum_conf >magnum_tmp.conf 2>add-params-to-conf.stderr
    sed -e 's/MS_data_file = \\S\\+/MS_data_file = $mzml_file/g' magnum_tmp.conf >magnum_fixed.conf 2>>add-params-to-conf.stderr

    echo "DONE!" # Needed for proper exit
    """
}