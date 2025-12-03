process YARP {
    publishDir "${params.result_dir}/yarp", failOnError: true, mode: 'copy'
    label 'process_low'
    label 'error_retry'
    container params.images.yarp

    input:
        path fasta_file
        path magnum_conf
        val  decoy_ok

    output:
        path("${fasta_file.baseName}.plus-decoys.fasta"), emit: fasta_decoys

    script:
    """
    set -euo pipefail

    fasta="${fasta_file}"
    conf_file="${magnum_conf}"

    echo "Using Magnum config: \$conf_file" >&2

    # Extract decoy_filter line
    raw=\$(grep -E '^[[:space:]]*decoy_filter[[:space:]]*=' "\$conf_file" | head -n 1 || true)
    if [ -z "\$raw" ]; then
        echo "ERROR: No 'decoy_filter = ...' line found in Magnum config: \$conf_file" >&2
        exit 1
    fi
    conf=\${raw%%#*}
    rhs=\${conf#*=}
    rhs=\$(echo "\$rhs" | awk '{\$1=\$1; print}')
    decoy_prefix=\$(echo "\$rhs" | awk '{print \$1}')

    if [ -z "\$decoy_prefix" ]; then
        echo "ERROR: Could not parse decoy prefix from decoy_filter line: '\$raw'" >&2
        echo "       Expected something like: decoy_filter = DECOY_ 1" >&2
        exit 1
    fi

    echo "Using YARP to add decoys to \$fasta with prefix '\$decoy_prefix'..." >&2

    yarp \
        --fasta-file "\$fasta" \
        --decoy-method reverse \
        --decoy-prefix "\$decoy_prefix" \
        >"${fasta_file.baseName}.plus-decoys.fasta" 2>> >(tee yarp.stderr >&2)

    echo "Done!"
    """

    stub:
    """
    touch ${fasta_file.baseName}.plus-decoys.fasta
    """
}
