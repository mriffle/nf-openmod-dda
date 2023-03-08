def exec_java_command(mem) {
    def xmx = "-Xmx${mem.toGiga()-1}G"
    return "java -Djava.aws.headless=true ${xmx} -jar /usr/local/bin/magnumToLimelightXML.jar"
}

process CONVERT_TO_LIMELIGHT_XML {
    publishDir "${params.result_dir}/limelight", failOnError: true, mode: 'copy'
    label 'process_low'
    label 'process_high_memory'
    container 'mriffle/magnum-percolator-to-limelight:4.4.0'

    input:
        path pepxml
        path pout
        path fasta
        path magnum_conf

    output:
        path("results.limelight.xml"), emit: limelight_xml
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
    """
    echo "Running Limelight XML conversion..."
        ${exec_java_command(task.memory)} \
        -m ${pepxml} \
        -c ${magnum_conf} \
        -f ${fasta} \
        -p ${pout} \
        -o results.limelight.xml \
        -v \
        1>limelight-xml-convert.stdout 2>limelight-xml-convert.stderr

    echo "Done!" # Needed for proper exit
    """

    stub:
    """
    touch "results.limelight.xml"
    """
}
