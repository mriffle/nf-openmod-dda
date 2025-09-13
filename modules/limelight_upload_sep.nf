def exec_java_command(mem) {
    def xmx = "-Xmx${mem.toGiga()-1}G"
    return "java -Djava.aws.headless=true ${xmx} -jar /usr/local/bin/limelightSubmitImport.jar"
}

process UPLOAD_TO_LIMELIGHT_SEP {
    publishDir "${params.result_dir}/limelight/${sample_id}", failOnError: true, mode: 'copy'
    label 'process_low'
    container params.images.limelight_submit

    input:
        tuple val(sample_id), path(mzml_file), path(limelight_xml)
        path fasta
        val webapp_url
        val project_id
        val search_long_name
        val search_short_name
        val tags

    output:
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
    tags_param = ''
    if(tags) {
        tags_param = "--search-tag=\"${tags.split(',').join('\" --search-tag=\"')}\""
    }

    search_description_param = search_long_name == null ? '' : "--search-description=\"(${sample_id}) ${search_long_name}\""

    """
    echo "Submitting search results for Limelight import for ${sample_id}..."
        ${exec_java_command(task.memory)} \
        --retry-count-limit=5 \
        --limelight-web-app-url=${webapp_url} \
        --user-submit-import-key=\$LIMELIGHT_SUBMIT_UPLOAD_KEY \
        --project-id=${project_id} \
        --limelight-xml-file=${limelight_xml} \
        --fasta-file=${fasta} \
        --search-description="${search_long_name} (${sample_id})" \
        --path="${workflow.launchDir}" \
        --scan-file=${mzml_file} \
        ${tags_param} \
        > >(tee "limelight-submit-upload.stdout") 2> >(tee "limelight-submit-upload.stderr" >&2)
        
    echo "Done!"
    """

    stub:
    """
    touch "limelight-submit-upload.stdout"
    touch "limelight-submit-upload.stderr"
    """
}
