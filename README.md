# nf-openmod-dda
A Nextflow workflow for performing an open modification search and
optional subsequent upload to Limelight (https://limelight-ms.org/)
for visualization, sharing, and analysis.

The workflow currently runs:

- msconvert (if raw files are used as input) (https://proteowizard.sourceforge.io/index.html)
- magnum (https://magnum-ms.org/)
- percolator (http://percolator.ms/)
- Limelight XML conversion (https://github.com/yeastrc/limelight-import-magnum-percolator)
- Limelight uploader

## Parameters
This workflow accepts the following parameters:

- `magnum_conf` - `required` Path to the Magnum conf file to use for the search. See https://raw.githubusercontent.com/mriffle/nf-openmod-dda/main/example_files/Magnum.conf for example `Magnum.conf`.
- `fasta` - `required` Path to the original, unfiltered FASTA file
- `spectra_dir` - `required` Path to a directory containing either raw or mzML files. If mzML files are found, raw files will be ignored. 
- `email` - To whom a completion email should be sent. Exclude this parameter to send no email. Default is to send no email.
- `limelight_upload` - Leave out or set to false to not upload to Limelight. Set to true to upload to Limelight.

If uploading to Limelight, the following parameters are required:
- `limelight_webapp_url` - The URL of the Limelight web application you are uploading to.
- `limelight_search_description` - The one-line description of this search to send to Limelight.
- `limelight_search_short_name` - A very brief label used to refer to this search in charts and tables.
- `limelight_tags` - (`optional`) A comma-delimited list of tags to send to Limelight for this search.

The following parameters control where data are cached to save time with subsequent processing:
- `mzml_cache_directory` - The cache directory to use when converting raw files to mzML. Default: `/data/mass_spec/nextflow/nf-filter-fasta/mzml_cache`
- `panorama_cache_directory` - The cache directory to use when downloading raw files from PanoramaWeb. Default: `/data/mass_spec/nextflow/panorama/raw_cache`

## How To Use
Use the following command(s) to run the workflow:

- To ensure latest version of workflow is installed:

  `nextflow pull -r main mriffle/nf-filter-fasta`

- To run the workflow specifying parameters on command line:

  `nextflow run -r main mriffle/nf-filter-fasta --comet_params /path/to/comet.params --spectra_dir /path/to/mzml_files --fasta /path/to/file.fasta`

- To run workflow using a configuration file:

  Create configuration file called `pipeline.config` in this example (can be called anything). You can put any of the parameters above in it as:

  ```
  params {
    comet_params = '/path/to/comet.params'
    fasta = '/path/to/file.fasta'
    spectra_dir  = '/path/to/mzml_files'
    psm_qvalue_filter = 0.05
  }
  ```

  Then run the workflow using:

  `nextflow run -r main mriffle/nf-filter-fasta -c pipeline.config`

## Output
The output of the pipeline will be placed in the `results/nf-filter-fasta` directory (relative to where the workflow was run). Assuming your FASTA file was named `myname.fasta` the output files include:
- `fasta/myname.filtered.fasta` - The FASTA file that has been filtered using comet/percolator results.
- `fasta/myname.filtered.fixed.fasta` - The above file after it has been "fixed" (any duplicate entries removed and sequences containing invalid residues removed).
- `fasta/myname.filtered.fixed.plusdecoys.fasta` - The above file that has had decoys added.
- `comet/*.pin` - The percolator input files generated by the comet search.
- `comet/*.pep.xml` - The comet results files.
- `percolator/combined_filtered.pout.xml` - The percolator results.

## PanoramaWeb Integration

1. You must first set up your PanoramaWeb credentials. After finding your API KEY in PanoramaWeb save it to Nextflow by typing:

   `nextflow secrets set PANORAMA_API_KEY "api key from PanoramaWeb"`

2. All file locations that begin with `https://` are assumed to be PanoramaWeb WebDAV URLs. To specify PanoramaWeb locations for all input files, the following `pipeline.config` file could be used:

    ```
    params {
        comet_params = 'https://panoramaweb.org/_webdav/FOLDER_PATH/@files/comet.params'
        fasta = 'https://panoramaweb.org/_webdav/FOLDER_PATH/@files/myname.fasta'
        spectra_dir  = 'https://panoramaweb.org/_webdav/FOLDER_PATH/@files/FOLDER_NAME/'
        psm_qvalue_filter = 0.05
    }
    ```
    Note: it is not required that all files be in PanoramaWeb, mixing local and PanoramaWeb files will work.

