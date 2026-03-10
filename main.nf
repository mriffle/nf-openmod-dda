#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

// modules
include { PANORAMA_GET_FASTA } from "./modules/panorama"
include { PANORAMA_GET_COMET_PARAMS } from "./modules/panorama"
include { PANORAMA_GET_MAGNUM_CONF } from "./modules/panorama"
include { PANORAMA_GET_RAW_FILE } from "./modules/panorama"
include { PANORAMA_GET_RAW_FILE_LIST } from "./modules/panorama"
include { YARP } from "./modules/yarp"
include { VALIDATE_DECOY_OPTIONS } from "./modules/validate_decoy_options"

// Sub workflows
include { wf_magnum_combined_percolator } from "./workflows/magnum_percolator_combined"
include { wf_magnum_separate_percolator } from "./workflows/magnum_percolator_separate"

def normalize_pin_columns_to_remove(pin_columns_param) {
    if (pin_columns_param == null) {
        return []
    }

    if (pin_columns_param instanceof CharSequence) {
        return pin_columns_param
            .toString()
            .split(',')
            .collect { it.trim() }
            .findAll { it }
    }

    if (pin_columns_param instanceof Collection) {
        return pin_columns_param
            .collect { it.toString().trim() }
            .findAll { it }
    }

    error "Invalid value for --percolator_pin_columns_to_remove. Use a comma-delimited string or list of column names."
}

//
// The main workflow
//
workflow {

    magnum_conf_ch = Channel.fromPath(params.magnum_conf)

    if(params.fasta.startsWith("https://")) {
        PANORAMA_GET_FASTA(params.fasta)
        fasta = PANORAMA_GET_FASTA.out.panorama_file
    } else {
        fasta = file(params.fasta, checkIfExists: true)
    }

    if(params.magnum_conf.startsWith("https://")) {
        PANORAMA_GET_MAGNUM_CONF(params.magnum_conf)
        magnum_conf = PANORAMA_GET_MAGNUM_CONF.out.panorama_file
    } else {
        magnum_conf = file(params.magnum_conf, checkIfExists: true)
    }

    // ensure no inconsistencies in decoy logic
    // e.g. generating decoys when decoys are already present in FASTA
    VALIDATE_DECOY_OPTIONS(fasta, magnum_conf, params.generate_decoys)

    if(params.spectra_dir.contains("https://")) {

        spectra_dirs_ch = Channel.from(params.spectra_dir)
                                .splitText()               // split multiline input
                                .map{ it.trim() }          // removing surrounding whitespace
                                .filter{ it.length() > 0 } // skip empty lines

        // get raw files from panorama
        PANORAMA_GET_RAW_FILE_LIST(spectra_dirs_ch)
        placeholder_ch = PANORAMA_GET_RAW_FILE_LIST.out.raw_file_placeholders.transpose()
        PANORAMA_GET_RAW_FILE(placeholder_ch)
        
        spectra_files_ch = PANORAMA_GET_RAW_FILE.out.panorama_file
        from_raw_files = true;

    } else {

        spectra_dir = file(params.spectra_dir, checkIfExists: true)

        // get our mzML files
        mzml_files = file("$spectra_dir/*.mzML")

        // get our raw files
        raw_files = file("$spectra_dir/*.raw")

        if(mzml_files.size() < 1 && raw_files.size() < 1) {
            error "No raw or mzML files found in: $spectra_dir"
        }

        if(mzml_files.size() > 0) {
                spectra_files_ch = Channel.fromList(mzml_files)
                from_raw_files = false;
        } else {
                spectra_files_ch = Channel.fromList(raw_files)
                from_raw_files = true;
        }
    }

    if(params.generate_decoys) {
        YARP(fasta, magnum_conf, VALIDATE_DECOY_OPTIONS.out.decoy_ok)
        final_fasta = YARP.out.fasta_decoys
    } else {
        final_fasta = fasta
    }

    percolator_pin_columns_to_remove = normalize_pin_columns_to_remove(params.percolator_pin_columns_to_remove)

    if(params.process_separately) {
        wf_magnum_separate_percolator(
            spectra_files_ch,
            magnum_conf,
            final_fasta,
            from_raw_files,
            percolator_pin_columns_to_remove
        )
    } else {
        wf_magnum_combined_percolator(
            spectra_files_ch,
            magnum_conf,
            final_fasta,
            from_raw_files,
            percolator_pin_columns_to_remove
        )
    }

}

//
// Used for email notifications
//
def email() {
    // Create the email text:
    def (subject, msg) = EmailTemplate.email(workflow, params)
    // Send the email:
    if (params.email) {
        sendMail(
            to: "$params.email",
            subject: subject,
            body: msg
        )
    }
}

//
// This is a dummy workflow for testing
//
workflow dummy {
    println "This is a workflow that doesn't do anything."
}

// Email notifications:
workflow.onComplete {
    try {
        email()
    } catch (Exception e) {
        println "Warning: Error sending completion email."
    }
}
