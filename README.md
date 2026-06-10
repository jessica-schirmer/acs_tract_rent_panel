# Pipeline
## Project: ADU Rent
## Processing phase: Create ACS rent, rent change, and covariates dataset.
## Overview
This repository covers selection of variables, cleaning, and creation of analysis measures for 2012-2016 and 2019-2023 ACS for 2010 tracts.

01_acs.rmd - import selected variables from the 2012-2016 ACS (tracts) and 2019-2023 ACS (block groups); import cross-walk for 2023 block groups to 2010 tracts
02_assemble.rmd - import ACS data; merge 2019-2023 data with 2010 tract crosswalk and aggregate 2019-2023 block group variables to 2010 tracts; import missind data flags and uncertainty measures
03_merge.rmd - import 2023 ACS measures aggregated to 2010 tracts and merge w/ 2016 ACS measures; calculate change variables; save ACS tract panel



# Source / Inputs
Census API


# Processing Plan



## Step 1: Import ACS data
Script: `01_acs.rmd`


Inputs:
Outputs:
Schema: 

Steps:


## Step 2: Assemble geographically consistent tract measures for later years
Script: `02_assemble.rmd`
Inputs:

Outputs:

Steps:


## Step 3: Create ACS panel, calculate change variables
Script: `03_merge.rmd`
Inputs:

Outputs:

Steps:


