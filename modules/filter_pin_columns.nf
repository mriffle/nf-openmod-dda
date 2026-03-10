process FILTER_PIN_COLUMNS {
    publishDir "${params.result_dir}/percolator/${sample_id}", failOnError: true, mode: 'copy'
    label 'process_low_constant'
    container params.images.ubuntu

    input:
        tuple val(sample_id), path(pin_file)
        val columns_to_remove

    output:
        tuple val(sample_id), path("${sample_id}.columns_filtered.pin"), emit: pin
        path("*.stderr"), emit: stderr

    script:
    def normalized_columns = (columns_to_remove ?: []).collect { it.toString().trim() }.findAll { it }
    def columns_file_contents = normalized_columns.join('\n')
    """
    cat << 'EOF' > columns_to_remove.txt
${columns_file_contents}
EOF

    awk -v cols_file="columns_to_remove.txt" '
        BEGIN {
            FS = OFS = "\\t"
            while ((getline col < cols_file) > 0) {
                if (col != "") {
                    remove[col] = 1
                }
            }
            close(cols_file)
        }
        NR == 1 {
            for (i = 1; i <= NF; i++) {
                headers[i] = \$i
                if (headers[i] in remove) {
                    drop[i] = 1
                } else {
                    keep[++k] = i
                }
            }

            for (col in remove) {
                found = 0
                for (i = 1; i <= NF; i++) {
                    if (headers[i] == col) {
                        found = 1
                        break
                    }
                }
                if (!found) {
                    printf "ERROR: Requested PIN column not found: %s\\n", col > "/dev/stderr"
                    err = 1
                }
            }

            if (k < 1) {
                print "ERROR: Filtering would remove all PIN columns." > "/dev/stderr"
                err = 1
            }

            if (err) {
                exit 1
            }
        }
        {
            out = \$keep[1]
            for (j = 2; j <= k; j++) {
                out = out OFS \$keep[j]
            }
            print out
        }
    ' "${pin_file}" > "${sample_id}.columns_filtered.pin" 2> >(tee "${sample_id}.filter-pin.stderr" >&2)
    """

    stub:
    """
    touch "${sample_id}.columns_filtered.pin"
    touch "${sample_id}.filter-pin.stderr"
    """
}
