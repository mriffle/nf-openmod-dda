// Modules
include { MSCONVERT } from "../modules/msconvert"
include { MAGNUM } from "../modules/magnum"
include { PERCOLATOR } from "../modules/percolator"
include { ADD_PARAMS_TO_MAGNUM_CONF } from "../modules/add_params_to_magnum_conf"
include { CONVERT_TO_LIMELIGHT_XML_SEP as LIMELIGHT_XML_CONVERT_SEP } from "../modules/limelight_xml_convert_sep"
include { UPLOAD_TO_LIMELIGHT_SEP as LIMELIGHT_UPLOAD_SEP } from "../modules/limelight_upload_sep"

workflow wf_magnum_separate_percolator {

    take:
        spectra_file_ch
        magnum_conf
        fasta
        from_raw_files

    main:


        // convert raw files to mzML files if necessary
        if(from_raw_files) {
            MSCONVERT(spectra_file_ch)
            mzml_file_ch = MSCONVERT.out.mzml
        } else {
            mzml_file_ch = spectra_file_ch.map { mzml_file -> 
                tuple(mzml_file.baseName, mzml_file) 
            }
        }

        ADD_PARAMS_TO_MAGNUM_CONF(
            mzml_file_ch,
            magnum_conf,
            fasta
        )

        MAGNUM(ADD_PARAMS_TO_MAGNUM_CONF.out.magnum_job_tuple, fasta)

        PERCOLATOR(MAGNUM.out.pin)

        if (params.limelight_upload) {

            // Create paired channel by joining MAGNUM and PERCOLATOR outputs
            // Both outputs have the same sample ID (base name of original raw file)
            paired_results = MAGNUM.out.pepxml
                .join(PERCOLATOR.out.pout)
                .map { sample_id, magnum_pepxml, percolator_pout ->
                    tuple(sample_id, magnum_pepxml, percolator_pout)
                }

            magnum_conf_ch = ADD_PARAMS_TO_MAGNUM_CONF.out.magnum_job_tuple.map { it -> tuple(it[0], it[2]) }

            LIMELIGHT_XML_CONVERT_SEP(
                paired_results,
                magnum_conf_ch,
                fasta
            )

            // Create paired channel for mzML files and limelight XML outputs
            upload_pairs = mzml_file_ch
                .join(LIMELIGHT_XML_CONVERT_SEP.out.limelight_xml)
                .map { sample_id, spectra_file, limelight_xml ->
                    tuple(sample_id, spectra_file, limelight_xml)
                }

            LIMELIGHT_UPLOAD_SEP(
                upload_pairs,
                fasta,
                params.limelight_webapp_url,
                params.limelight_project_id,
                params.limelight_search_description,
                params.limelight_search_short_name,
                params.limelight_tags
            )
        }

}
