// Modules
include { MSCONVERT } from "../modules/msconvert"
include { MAGNUM } from "../modules/magnum"
include { PERCOLATOR } from "../modules/percolator"
include { COMBINE_PIN_FILES } from "../modules/combine_pin_files"
include { ADD_PARAMS_TO_MAGNUM_CONF } from "../modules/add_params_to_magnum_conf"
include { CONVERT_TO_LIMELIGHT_XML } from "../modules/limelight_xml_convert"
include { UPLOAD_TO_LIMELIGHT } from "../modules/limelight_upload"

workflow wf_magnum_percolator {

    take:
        spectra_file_ch
        magnum_conf
        fasta
        from_raw_files
    
    main:

        // convert raw files to mzML files if necessary
        if(from_raw_files) {
            mzml_file_ch = MSCONVERT(spectra_file_ch)
        } else {
            mzml_file_ch = spectra_file_ch
        }

        // add items to magnum conf
        ADD_PARAMS_TO_MAGNUM_CONF(magnum_conf, fasta, mzml_file_ch)
        MAGNUM(ADD_PARAMS_TO_MAGNUM_CONF.out.magnum_job_tuple, fasta)
        pin_files = MAGNUM.out.pin.collect()
        COMBINE_PIN_FILES(pin_files)
        PERCOLATOR(COMBINE_PIN_FILES.out.combined_pin)

        if (params.limelight_upload) {

            CONVERT_TO_LIMELIGHT_XML(
                MAGNUM.out.pepxml.collect(), 
                PERCOLATOR.out.pout, 
                fasta, 
                magnum_conf
            )

            UPLOAD_TO_LIMELIGHT(
                CONVERT_TO_LIMELIGHT_XML.out.limelight_xml,
                mzml_file_ch.collect(),
                params.limelight_webapp_url,
                params.limelight_project_id,
                params.limelight_search_description,
                params.limelight_search_short_name,
                params.limelight_tags,
            )
        }

}
