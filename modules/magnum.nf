process MAGNUM {
    publishDir "${params.result_dir}/magnum", failOnError: true, mode: 'copy'
    label 'process_high_constant'
    container 'quay.io/protio/magnum:1.4.0'

    input:
        tuple path(mzml_file), path(magnum_conf)
        path fasta_file

    output:
        path("*.pep.xml"), emit: pepxml
        path("*.perc.txt"), emit: pin
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr
        path("*.diag.xml"), emit: diagxml, optional: true

    script:
    """
    echo "Running magnum..."
    magnum magnum_fixed.conf \
        > >(tee "${mzml_file.baseName}.magnum.stdout") 2> >(tee "${mzml_file.baseName}.magnum.stderr" >&2)

    echo "DONE!" # Needed for proper exit
    """

    stub:
    """
    touch "${mzml_file.baseName}.pep.xml"
    touch "${mzml_file.baseName}.perc.txt"
    """
}
