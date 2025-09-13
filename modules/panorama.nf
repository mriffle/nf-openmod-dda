// Modules/process for interacting with PanoramaWeb

def exec_java_command(mem) {
    def xmx = "-Xmx${mem.toGiga()-1}G"
    return "java -Djava.aws.headless=true ${xmx} -jar /usr/local/bin/PanoramaClient.jar"
}

process PANORAMA_GET_RAW_FILE_LIST {
    label 'process_low_constant'
    container params.images.panorama_client
    publishDir "${params.result_dir}/panorama", failOnError: true, mode: 'copy'

    input:
        each web_dav_url

    output:
        tuple val(web_dav_url), path("*.download"), emit: raw_file_placeholders
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
    """
    echo "Running file list from Panorama..."
        ${exec_java_command(task.memory)} \
        -l \
        -e raw \
        -w "${web_dav_url}" \
        -k \$PANORAMA_API_KEY \
        -o panorama_files.txt \
        > >(tee "panorama-get-files.stdout") 2> >(tee "panorama-get-files.stderr" >&2) && \
        cat panorama_files.txt | xargs -I % sh -c 'touch %.download'

    echo "Done!" # Needed for proper exit
    """

    stub:
    """
    touch "placeholder.download"
    touch "panorama-get-files.stdout"
    touch "panorama-get-files.stderr"
    """
}

process PANORAMA_GET_FASTA {
    label 'process_low_constant'
    container params.images.panorama_client
    publishDir "${params.result_dir}/panorama", failOnError: true, mode: 'copy', pattern: "*.stdout"
    publishDir "${params.result_dir}/panorama", failOnError: true, mode: 'copy', pattern: "*.stderr"

    input:
        val web_dav_dir_url

    output:
        path("${file(web_dav_dir_url).name}"), emit: panorama_file
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
        file_name = file(web_dav_dir_url).name
        """
        echo "Downloading ${file_name} from Panorama..."
            ${exec_java_command(task.memory)} \
            -d \
            -w "${web_dav_dir_url}" \
            -k \$PANORAMA_API_KEY \
            > >(tee "panorama-get-${file_name}.stdout") 2> >(tee "panorama-get-${file_name}.stderr" >&2)
        echo "Done!" # Needed for proper exit
        """

    stub:
    {
        def file_name = file(web_dav_dir_url).name
        """
        touch "${file_name}"
        touch "panorama-get-${file_name}.stdout"
        touch "panorama-get-${file_name}.stderr"
        """
    }
}

process PANORAMA_GET_COMET_PARAMS {
    label 'process_low_constant'
    container params.images.panorama_client
    publishDir "${params.result_dir}/panorama", failOnError: true, mode: 'copy', pattern: "*.stdout"
    publishDir "${params.result_dir}/panorama", failOnError: true, mode: 'copy', pattern: "*.stderr"

    input:
        val web_dav_dir_url

    output:
        path("${file(web_dav_dir_url).name}"), emit: panorama_file
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
        file_name = file(web_dav_dir_url).name
        """
        echo "Downloading ${file_name} from Panorama..."
            ${exec_java_command(task.memory)} \
            -d \
            -w "${web_dav_dir_url}" \
            -k \$PANORAMA_API_KEY \
            > >(tee "panorama-get-${file_name}.stdout") 2> >(tee "panorama-get-${file_name}.stderr" >&2)
        echo "Done!" # Needed for proper exit
        """

    stub:
    {
        def file_name = file(web_dav_dir_url).name
        """
        touch "${file_name}"
        touch "panorama-get-${file_name}.stdout"
        touch "panorama-get-${file_name}.stderr"
        """
    }
}

process PANORAMA_GET_RAW_FILE {
    label 'process_low_constant'
    container params.images.panorama_client
    storeDir "${params.panorama_cache_directory}"

    input:
        tuple val(web_dav_dir_url), path(download_file_placeholder)

    output:
        path("${download_file_placeholder.baseName}"), emit: panorama_file
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
        raw_file_name = download_file_placeholder.baseName
        """
        echo "Downloading ${raw_file_name} from Panorama..."
            ${exec_java_command(task.memory)} \
            -d \
            -w "${web_dav_dir_url}${raw_file_name}" \
            -k \$PANORAMA_API_KEY \
            > >(tee "panorama-get-${raw_file_name}.stdout") 2> >(tee "panorama-get-${raw_file_name}.stderr" >&2)
        echo "Done!" # Needed for proper exit
        """

    stub:
    {
        def raw_file_name = download_file_placeholder.baseName
        """
        touch "${raw_file_name}"
        touch "panorama-get-${raw_file_name}.stdout"
        touch "panorama-get-${raw_file_name}.stderr"
        """
    }
}
