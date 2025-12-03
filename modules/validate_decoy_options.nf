process VALIDATE_DECOY_OPTIONS {

    tag "$fasta"

    input:
    path fasta
    path magnum_conf
    val  generate_decoys

    output:
    val(true) into decoy_ok_ch

    script:
    """
    set -euo pipefail

    fasta="!{fasta}"
    magnum_conf="!{magnum_conf}"
    generate_decoys_str="!{generate_decoys}"

    # Extract the decoy_filter line
    raw=\$(grep -E '^[[:space:]]*decoy_filter[[:space:]]*=' "\$magnum_conf" | head -n 1 || true)

    if [ -z "\$raw" ]; then
        echo "ERROR: No 'decoy_filter = ...' line found in Magnum config: \$magnum_conf" >&2
        exit 1
    fi

    # Strip trailing comments (anything after '#')
    conf=\${raw%%#*}

    # Get the RHS after '=' and trim whitespace
    rhs=\${conf#*=}
    rhs=\$(echo "\$rhs" | awk '{\$1=\$1; print}')   # trim leading/trailing spaces

    # Expect: <decoy_prefix> <flag>, e.g. 'DECOY_ 0'
    decoy_prefix=\$(echo "\$rhs" | awk '{print \$1}')
    flag=\$(echo "\$rhs" | awk '{print \$2}')

    if [ -z "\$decoy_prefix" ] || [ -z "\$flag" ]; then
        echo "ERROR: Could not parse decoy_filter line in \$magnum_conf: '\$raw'" >&2
        echo "       Expected something like: decoy_filter = DECOY_ 0" >&2
        exit 1
    fi

    echo "INFO: Parsed decoy_filter from Magnum.conf: prefix='\$decoy_prefix', flag=\$flag" >&2

    # Count decoy entries in the FASTA (headers starting with >PREFIX)
    decoy_count=\$(grep -c "^>\$decoy_prefix" "\$fasta" || true)
    echo "INFO: Found \$decoy_count FASTA headers starting with '>\$decoy_prefix' in \$fasta" >&2

    # -----------------------------
    # ERROR CASE 1:
    # generate_decoys=false AND Magnum flag=0 (database has decoys)
    # BUT decoy_count == 0 => error
    # -----------------------------
    if [ "\$generate_decoys_str" = "false" ] && [ "\$flag" = "0" ]; then
        if [ "\$decoy_count" -eq 0 ]; then
            echo "ERROR: generate_decoys=false and Magnum decoy_filter flag=0," >&2
            echo "       so the FASTA is expected to already contain decoys." >&2
            echo "       However, no headers in '\$fasta' start with '>\$decoy_prefix'." >&2
            echo "       Example expected header: >\${decoy_prefix}PROTEIN_X" >&2
            exit 1
        fi
    fi

    # -----------------------------
    # ERROR CASE 2:
    # generate_decoys=true BUT decoys already present in FASTA
    # (regardless of Magnum flag) => error
    # -----------------------------
    if [ "\$generate_decoys_str" = "true" ] && [ "\$decoy_count" -gt 0 ]; then
        echo "ERROR: generate_decoys=true but FASTA '\$fasta' already contains \$decoy_count" >&2
        echo "       decoy entries with prefix '\$decoy_prefix'." >&2
        echo "       Either:" >&2
        echo "         - set generate_decoys=false and keep the existing decoys, OR" >&2
        echo "         - remove the decoy entries from the FASTA and let Magnum generate them." >&2
        exit 1
    fi

    # If we get here, all checks passed (or conditions didn’t apply)
    """
}
