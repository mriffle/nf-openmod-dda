# nf-openmod-dda
A Nextflow workflow for performing an open modification search and
optional subsequent upload to Limelight (https://limelight-ms.org/)
for visualization, sharing, and analysis.

## Documentation
Full documentation can be found at https://nf-openmod-dda.readthedocs.io/.

The workflow currently runs:

- msconvert (if raw files are used as input) (https://proteowizard.sourceforge.io/index.html)
- magnum (https://magnum-ms.org/)
- percolator (http://percolator.ms/)
- Limelight XML conversion (https://github.com/yeastrc/limelight-import-magnum-percolator)
- Limelight uploader

## Parameters
This workflow accepts the following parameters:

- `magnum_conf` - `required` Path to the Magnum conf file to use for the search. See https://raw.githubusercontent.com/mriffle/nf-openmod-dda/main/example_files/Magnum.conf for example `Magnum.conf`.
- `fasta` - `required` Path to the FASTA file
- `spectra_dir` - `required` Path to a directory containing either raw or mzML files. If mzML files are found, raw files will be ignored. 
- `process_separately` - `(optional)` Set to `true` to run Percolator and Limelight upload separately for each input file. If `false` (the default), results from all input files are combined before running Percolator and uploading to Limelight. Note: Combining output for Percolator may result in better statistics, but it makes it harder to compare the results from individual raw files to other searches that were not a part of that Percolator run. Default: `false`.
- `email` - To whom a completion email should be sent. Exclude this parameter to send no email. Default is to send no email.
- `limelight_upload` - Leave out or set to false to not upload to Limelight. Set to true to upload to Limelight.

If uploading to Limelight, the following parameters are required:
- `limelight_webapp_url` - The URL of the Limelight web application you are uploading to. Can be obtained by expanding the "Upload Data" section on the project page and and clicking the "Command Line Import Info" button. 
- `limelight_project_id` - The numeric ID of the Limelight project to upload the data to. Can be obtained by expanding the "Upload Data" section on the project page and and clicking the "Command Line Import Info" button. 
- `limelight_search_description` - The one-line description of this search to send to Limelight.
- `limelight_search_short_name` - A very brief label used to refer to this search in charts and tables.
- `limelight_tags` - `(optional)` A comma-delimited list of tags to send to Limelight for this search.

The following parameters control where data are cached to save time with subsequent processing:
- `mzml_cache_directory` - The cache directory to use when converting raw files to mzML. Default: `/data/mass_spec/nextflow/nf-openmod-dda/mzml_cache`
- `panorama_cache_directory` - The cache directory to use when downloading raw files from PanoramaWeb. Default: `/data/mass_spec/nextflow/panorama/raw_cache`

## How To Use
Use the following command(s) to run the workflow:

- To ensure latest version of workflow is installed:

  `nextflow pull -r main mriffle/nf-openmod-dda`

- To run the workflow specifying parameters on command line:

  `nextflow run -r main mriffle/nf-openmod-dda --magnum_conf /path/to/Magnum.conf --spectra_dir /path/to/mzml_files --fasta /path/to/file.fasta`

- To run workflow using a configuration file:

  Create configuration file called `pipeline.config` in this example (can be called anything). You can put any of the parameters above in it as:

  ```
  params {
    magnum_conf = '/path/to/Magnum.conf'
    fasta = '/path/to/file.fasta'
    spectra_dir  = '/path/to/mzml_files'
    
    limelight_upload = true
    limelight_webapp_url = 'change to your limelight URL'
    limelight_search_description = 'Open mod search of yeast grown in space.'
    limelight_search_short_name = 'spaceyeast'
    limelight_tags = 'space,yeast,magnum,percolator'
  }
  ```

  Then run the workflow using:

  `nextflow run -r main mriffle/nf-openmod-dda -c pipeline.config`

## Output
The output of the pipeline will be placed in the `results/nf-openmod-dda` directory (relative to where the workflow was run). `BASENAME` is the base part of the mzML or raw filename (e.g., `my_file.raw` would have a `BASENAME` of `my_file`):

- `magnum/magnum_fixed.conf` - Magnum conf file after modification by the workflow (adding in the FASTA and mzML files).
- `magnum/BASENAME.pep.xml` - Magnum results in PepXML format.
- `magnum/BASENAME.perc.txt` - Magnum results as input to Percolator.

If `process_separately` is `false` (default):
- `percolator/combined.filtered.pin` - Percolator input file resulting from combining all percolator input files.
- `percolator/combined.filtered.pout.xml` - Percolator PSM and peptide results for the combined data.
- `limelight/results.limelight.xml` - The Limelight XML representation of the combined results (if uploading to Limelight).

If `process_separately` is `true`:
- `percolator/BASENAME.filtered.pin` - Percolator input file for each respective input file.
- `percolator/BASENAME.filtered.pout.xml` - Percolator PSM and peptide results for each respective input file.
- `limelight/BASENAME.limelight.xml` - The Limelight XML representation of the results for each respective input file (if uploading to Limelight).

## Limelight Integration
To upload results to Limelight, you must first set up your Limelight credentials. To find your api key, expand the "Upload Data" section on the project page and and click the "Command Line Import Info" button. Then enter the following on your command line (where the workflow is being run):

   `nextflow secrets set LIMELIGHT_SUBMIT_UPLOAD_KEY "api key from Limelight"`

## PanoramaWeb Integration
1. To use PanoramaWeb as the source for input files, you must first set up your PanoramaWeb credentials. After finding your API KEY in PanoramaWeb save it to Nextflow by typing:

   `nextflow secrets set PANORAMA_API_KEY "api key from PanoramaWeb"`

2. All file locations that begin with `https://` are assumed to be PanoramaWeb WebDAV URLs. To specify PanoramaWeb locations for all input files, the following `pipeline.config` file could be used:

    ```
    params {
        magnum_conf = '/path/to/Magnum.conf'
        fasta = 'https://panoramaweb.org/_webdav/FOLDER_PATH/@files/myname.fasta'
        spectra_dir  = 'https://panoramaweb.org/_webdav/FOLDER_PATH/@files/FOLDER_NAME/'
    }
    ```
    Note: it is not required that all files be in PanoramaWeb, mixing local and PanoramaWeb files will work.

