process VALIDATE_DECOY_OPTIONS {

    input:
        path fasta
        path magnum_conf
        val  generate_decoys

    output:
        val(true), emit: decoy_ok

    script:
    """
    set -euo pipefail

    fasta="${fasta}"
    conf_file="${magnum_conf}"
    generate_decoys_str="${generate_decoys}"

    echo "Using Magnum config: \$conf_file" >&2

    # 1) Extract the decoy_filter line
    raw=\$(grep -E '^[[:space:]]*decoy_filter[[:space:]]*=' "\$conf_file" | head -n 1 || true)

    if [ -z "\$raw" ]; then
        echo "ERROR: No 'decoy_filter = ...' line found in Magnum config: \$conf_file" >&2
        exit 1
    fi

    # 2) Strip trailing comments (anything after '#')
    conf=\${raw%%#*}

    # 3) Get the RHS after '=' and trim whitespace
    rhs=\${conf#*=}
    rhs=\$(echo "\$rhs" | awk '{\$1=\$1; print}')   # trim leading/trailing spaces

    # Expect: <decoy_prefix> <flag>, e.g. 'DECOY_ 0'
    decoy_prefix=\$(echo "\$rhs" | awk '{print \$1}')
    flag=\$(echo "\$rhs" | awk '{print \$2}')

    if [ -z "\$decoy_prefix" ] || [ -z "\$flag" ]; then
        echo "ERROR: Could not parse decoy_filter line in \$conf_file: '\$raw'" >&2
        echo "       Expected something like: decoy_filter = DECOY_ 0" >&2
        exit 1
    fi

    echo "INFO: Parsed decoy_filter: prefix='\$decoy_prefix', flag=\$flag" >&2

    # Count decoy entries in the FASTA
    decoy_count=\$(grep -c "^>\$decoy_prefix" "\$fasta" || true)
    echo "INFO: Found \$decoy_count FASTA headers starting with '>\$decoy_prefix' in \$fasta" >&2

    # ERROR CASE 1:
    # generate_decoys=false AND flag=0 (db has decoys) BUT decoy_count == 0
    if [ "\$generate_decoys_str" = "false" ] && [ "\$flag" = "0" ]; then
        if [ "\$decoy_count" -eq 0 ]; then
            echo "ERROR: generate_decoys=false and Magnum decoy_filter flag=0," >&2
            echo "       so the FASTA is expected to already contain decoys." >&2
            echo "       However, no headers in '\$fasta' start with '>\$decoy_prefix'." >&2
            echo "       Example expected header: >\${decoy_prefix}PROTEIN_X" >&2
            exit 1
        fi
    fi

    # ERROR CASE 2:
    # generate_decoys=true BUT decoys already present
    if [ "\$generate_decoys_str" = "true" ] && [ "\$decoy_count" -gt 0 ]; then
        echo "ERROR: generate_decoys=true but FASTA '\$fasta' already contains \$decoy_count" >&2
        echo "       decoy entries with prefix '\$decoy_prefix'." >&2
        echo "       Either:" >&2
        echo "         - set generate_decoys=false and keep the existing decoys, OR" >&2
        echo "         - remove the decoy entries from the FASTA and let Magnum generate them." >&2
        exit 1
    fi

    echo "Input validation passed for \$fasta" >&2
    """
}
