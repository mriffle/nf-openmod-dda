process MSCONVERT {
    storeDir "${params.mzml_cache_directory}"
    label 'process_medium'
    label 'error_retry'
    container 'chambm/pwiz-skyline-i-agree-to-the-vendor-licenses:3.0.22335-b595b19'

    input:
        path raw_file

    output:
        path("${raw_file.baseName}.mzML"), emit: mzml_file

    script:
    """
    wine msconvert \\
        ${raw_file} \\
        -v \\
        --zlib \\
        --mzML \\
        --64 \\
        --filter "peakPicking true 1-"
    """

    stub:
    """
    touch ${raw_file.baseName}.mzML
    """
}
