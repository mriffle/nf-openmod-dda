def exec_java_command(mem) {
    def xmx = "-Xmx${mem.toGiga()-1}G"
    return "java -Djava.aws.headless=true ${xmx} -jar /usr/local/bin/magnumToLimelightXML.jar"
}

process CONVERT_TO_LIMELIGHT_XML_SEP {
    publishDir "${params.result_dir}/limelight/${sample_id}", failOnError: true, mode: 'copy'
    label 'process_low'
    label 'process_high_memory'
    label 'process_long'
    container params.images.magnum_to_limelight

    input:
        tuple val(sample_id), path(pepxml), path(pout)
        tuple val(sample_id_conf), path(magnum_conf)
        path fasta

    output:
        tuple val(sample_id), path("${sample_id}.limelight.xml"), emit: limelight_xml
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
    """
    echo "Running Limelight XML conversion for ${sample_id}..."
        ${exec_java_command(task.memory)} \
        --magnum=${pepxml} \
        -c ${magnum_conf} \
        -f ${fasta} \
        -p ${pout} \
        -o ${sample_id}.limelight.xml \
        -v \
        > >(tee "limelight-xml-convert.stdout") 2> >(tee "limelight-xml-convert.stderr" >&2)

    echo "Done!"
    """

    stub:
    """
    touch "${sample_id}.limelight.xml"
    touch "limelight-xml-convert.stdout"
    touch "limelight-xml-convert.stderr"
    """
}
