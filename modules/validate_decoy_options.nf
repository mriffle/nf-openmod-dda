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

    # Expect: <decoy_prefix> <flag>, e.g. 'DECOY_ 0' or 'DECOY_ 1'
    decoy_prefix=\$(echo "\$rhs" | awk '{print \$1}')
    flag=\$(echo "\$rhs" | awk '{print \$2}')

    if [ -z "\$decoy_prefix" ] || [ -z "\$flag" ]; then
        echo "ERROR: Could not parse decoy_filter line in \$conf_file: '\$raw'" >&2
        echo "       Expected something like: decoy_filter = DECOY_ 0" >&2
        echo "       Where: 0 = database already has decoys, 1 = Magnum should generate decoys." >&2
        exit 1
    fi

    echo "INFO: Parsed decoy_filter: prefix='\$decoy_prefix', flag=\$flag" >&2
    echo "INFO: generate_decoys (pipeline param) = \$generate_decoys_str" >&2

    # 4) Count decoy entries in the FASTA
    decoy_count=\$(grep -c "^>\$decoy_prefix" "\$fasta" || true)
    echo "INFO: Found \$decoy_count FASTA headers starting with '>\$decoy_prefix' in \$fasta" >&2

    # --------------------------------------------------------
    # ERROR CASE 1:
    # generate_decoys=false AND Magnum flag=0 (DB has decoys)
    # BUT decoy_count == 0 => config says DB has decoys, but FASTA does not
    # --------------------------------------------------------
    if [ "\$generate_decoys_str" = "false" ] && [ "\$flag" = "0" ]; then
        if [ "\$decoy_count" -eq 0 ]; then
            echo "ERROR: generate_decoys=false and Magnum decoy_filter flag=0," >&2
            echo "       so the FASTA is expected to already contain decoys." >&2
            echo "       However, no headers in '\$fasta' start with '>\$decoy_prefix'." >&2
            echo "       Example expected header: >\${decoy_prefix}PROTEIN_X" >&2
            exit 1
        fi
    fi

    # --------------------------------------------------------
    # ERROR CASE 2:
    # generate_decoys=true BUT decoys already present in FASTA
    # (regardless of Magnum flag) => don't double-decoy a DB that already has decoys
    # --------------------------------------------------------
    if [ "\$generate_decoys_str" = "true" ] && [ "\$decoy_count" -gt 0 ]; then
        echo "ERROR: generate_decoys=true but FASTA '\$fasta' already contains \$decoy_count" >&2
        echo "       decoy entries with prefix '\$decoy_prefix'." >&2
        echo "       Either:" >&2
        echo "         - set generate_decoys=false and keep the existing decoys, OR" >&2
        echo "         - remove the decoy entries from the FASTA and let Magnum/YARP generate them." >&2
        exit 1
    fi

    # --------------------------------------------------------
    # ERROR CASE 3:
    # generate_decoys=true AND Magnum flag=1 (Magnum also configured to generate decoys)
    # => configuration conflict: both pipeline and Magnum want to generate decoys
    # --------------------------------------------------------
    if [ "\$generate_decoys_str" = "true" ] && [ "\$flag" = "1" ]; then
        echo "ERROR: Both the pipeline and Magnum are configured to generate decoys." >&2
        echo "       - Pipeline param generate_decoys=true" >&2
        echo "       - Magnum decoy_filter flag=1 (Magnum will generate decoys)" >&2
        echo "       This would result in decoys being generated twice." >&2
        echo "       Please either:" >&2
        echo "         - set generate_decoys=false and let Magnum handle decoys, OR" >&2
        echo "         - set decoy_filter flag to 0 in Magnum.conf and let the pipeline generate decoys." >&2
        exit 1
    fi


    # --------------------------------------------------------
    # ERROR CASE 4:
    # Magnum flag=1 (Magnum will generate decoys)
    # BUT decoys already exist in the FASTA
    # => inconsistent: Magnum should NOT generate decoys on a DB that already has them
    # --------------------------------------------------------
    if [ "$flag" = "1" ] && [ "$decoy_count" -gt 0 ]; then
        echo "ERROR: Magnum is configured to generate decoys (decoy_filter flag=1)," >&2
        echo "       but the FASTA already contains $decoy_count decoy entries with prefix '$decoy_prefix'." >&2
        echo "       This would cause decoys to be generated twice or corrupt the target/decoy structure." >&2
        echo "       Please either:" >&2
        echo "         - remove decoys from the FASTA, OR" >&2
        echo "         - change decoy_filter flag to 0 in Magnum.conf." >&2
        exit 1
    fi

    echo "Input validation passed for \$fasta" >&2
    """
}
