process MSCONVERT {
    storeDir "${params.mzml_cache_directory}"
    label 'process_medium'
    label 'error_retry'
    container params.images.msconvert

    input:
        path raw_file

    output:
        tuple val(raw_file.baseName), path("${raw_file.baseName}.mzML"), emit: mzml

    script:
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
    """
    touch ${raw_file.baseName}.mzML
    """
}
