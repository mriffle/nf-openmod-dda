// Modules
include { MSCONVERT } from "../modules/msconvert"
include { MAGNUM } from "../modules/magnum"
include { PERCOLATOR } from "../modules/percolator"
include { COMBINE_PIN_FILES } from "../modules/combine_pin_files"
include { FILTER_PIN_COLUMNS } from "../modules/filter_pin_columns"
include { ADD_PARAMS_TO_MAGNUM_CONF } from "../modules/add_params_to_magnum_conf"
include { CONVERT_TO_LIMELIGHT_XML as LIMELIGHT_XML_CONVERT } from "../modules/limelight_xml_convert"
include { UPLOAD_TO_LIMELIGHT as LIMELIGHT_UPLOAD } from "../modules/limelight_upload"

workflow wf_magnum_combined_percolator {

    take:
        spectra_file_ch
        magnum_conf
        fasta
        from_raw_files
        pin_columns_to_remove

    main:


        // convert raw files to mzML files if necessary
        if(from_raw_files) {
            MSCONVERT(spectra_file_ch)
            mzml_file_ch = MSCONVERT.out.mzml.map { it[1] } // extract file from tuple
        } else {
            mzml_file_ch = spectra_file_ch
        }

        mzml_file_ch_for_add_params = mzml_file_ch.map { it -> tuple(it.baseName, it) }
        ADD_PARAMS_TO_MAGNUM_CONF(mzml_file_ch_for_add_params, magnum_conf, fasta)

        MAGNUM(ADD_PARAMS_TO_MAGNUM_CONF.out.magnum_job_tuple, fasta)

        pin_files = MAGNUM.out.pin.map { it[1] }.collect()

        COMBINE_PIN_FILES(pin_files)

        pin_for_percolator_ch = COMBINE_PIN_FILES.out.combined_pin.map { pin_file -> tuple("combined", pin_file) }

        if(pin_columns_to_remove.size() > 0) {
            FILTER_PIN_COLUMNS(pin_for_percolator_ch, pin_columns_to_remove)
            pin_for_percolator_ch = FILTER_PIN_COLUMNS.out.pin
        }

        PERCOLATOR(pin_for_percolator_ch)

        if (params.limelight_upload) {

            LIMELIGHT_XML_CONVERT(
                MAGNUM.out.pepxml.map { it[1] }.collect(),
                PERCOLATOR.out.pout.map { it[1] },
                fasta,
                magnum_conf
            )

            LIMELIGHT_UPLOAD(
                LIMELIGHT_XML_CONVERT.out.limelight_xml,
                mzml_file_ch.collect(),
                fasta,
                params.limelight_webapp_url,
                params.limelight_project_id,
                params.limelight_search_description,
                params.limelight_search_short_name,
                params.limelight_tags
            )
        }

}
