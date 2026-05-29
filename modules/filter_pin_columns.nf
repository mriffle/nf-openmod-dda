process FILTER_PIN_COLUMNS {
    publishDir { "${params.result_dir}/percolator/${sample_id}" }, failOnError: true, mode: 'copy'
    label 'process_low_constant'
    container params.images.ubuntu

    input:
        tuple val(sample_id), path(pin_file)
        val columns_to_remove

    output:
        tuple val(sample_id), path("${sample_id}.columns_filtered.pin"), emit: pin
        path("*.stderr"), emit: stderr

    script:
    def normalized_columns = (columns_to_remove ?: []).collect { col -> col.toString().trim() }.findAll { col -> col }
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
            # In a Magnum/Percolator PIN the trailing "Proteins" column is the last
            # header column, but each PSM may list additional proteins as extra,
            # header-less tab-separated columns. Treat everything from the protein
            # column onward as a single tail that is always preserved, and only
            # slice the columns before it.
            pcol = NF
            for (i = 1; i <= NF; i++) {
                headers[i] = \$i
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

            if (headers[pcol] in remove) {
                printf "ERROR: Refusing to remove the trailing protein column: %s\\n", headers[pcol] > "/dev/stderr"
                err = 1
            }

            nkeep = 0
            for (i = 1; i < pcol; i++) {
                if (!(headers[i] in remove)) {
                    keep[++nkeep] = i
                }
            }

            if (nkeep < 1) {
                print "ERROR: Filtering would remove all non-protein PIN columns." > "/dev/stderr"
                err = 1
            }

            if (err) {
                exit 1
            }
        }
        {
            out = ""
            for (j = 1; j <= nkeep; j++) {
                val = (keep[j] <= NF ? \$(keep[j]) : "")
                out = (j == 1 ? val : out OFS val)
            }
            tail = (pcol <= NF ? \$(pcol) : "")
            for (t = pcol + 1; t <= NF; t++) {
                tail = tail OFS \$t
            }
            print out OFS tail
        }
    ' "${pin_file}" > "${sample_id}.columns_filtered.pin" 2> "${sample_id}.filter-pin.stderr"
    """

    stub:
    """
    touch "${sample_id}.columns_filtered.pin"
    touch "${sample_id}.filter-pin.stderr"
    """
}
