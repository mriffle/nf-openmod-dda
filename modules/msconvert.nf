process MSCONVERT {
    storeDir "${params.mzml_cache_directory}"
    label 'process_medium'
    label 'error_retry'
    container params.images.msconvert

    input:
        path raw_file

    output:
        tuple val(sample_id), path("${raw_file.baseName}.mzML"), emit: mzml

    script:
    sample_id = raw_file.baseName
    """
    wine msconvert \
        ${raw_file} \
        -v \
        --zlib \
        --mzML \
        --64 \
        --filter "peakPicking true 1-"
    """

    stub:
    sample_id = raw_file.baseName
    """
    touch ${raw_file.baseName}.mzML
    """
}
