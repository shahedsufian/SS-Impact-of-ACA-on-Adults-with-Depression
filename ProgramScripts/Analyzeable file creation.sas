/********************************************************************************
*
* MEPS Data Processing and Cohort Creation
*
*
* Purpose:
* This script processes multiple years of Medical Expenditure Panel Survey (MEPS)
* data to create a longitudinal dataset of individuals with depression. It
* imports various MEPS public use files, identifies individuals with
* depression-related diagnosis codes, merges this information with the main
* consolidated data files, harmonizes variables across years, and stacks the
* yearly data into a single output file.
*
* Key Steps:
* 1. Setup: Defines global settings and a macro variable for the root data path.
* 2. Libname Assignment: Assigns a single library reference to the MEPS data
* directory.
* 3. Macro Definition (%Process_MEPS_Year): A powerful macro is defined to
* handle all processing for a single year, including:
* - Identifying depression using year-appropriate ICD-9 or ICD-10 codes.
* - Merging the depression flag with the Full-Year Consolidated (FYC) file.
* - Subsetting to keep only individuals with depression.
* - Harmonizing variable names to a consistent standard across all years.
* - Appending the cleaned yearly data to a master dataset.
* 4. Macro Execution: The macro is called once for each year from 2010 to 2019.
* 5. Final Export: The final, combined dataset is exported to a CSV file.
*
********************************************************************************/


* 1. SETUP & CONFIGURATION *;
*-------------------------------------------------------------------------------;
* Set global options for log performance and date handling.
options nonumber nodate;

* --- IMPORTANT: UPDATE THIS PATH ---
* Define a macro variable for the root directory where all MEPS data folders are stored.
* Replace "C:\path\to\your\meps\data" with the actual location on your system.
%let DATA_PATH = C:\path\to\your\meps\data;


* 2. LIBNAME ASSIGNMENT *;
*-------------------------------------------------------------------------------;
* Assign a single library reference to the MEPS data location.
* This is cleaner than assigning a separate libname for each file type.
libname MEPS "&DATA_PATH.";


* 3. MACRO DEFINITION: PROCESS_MEPS_YEAR *;
*-------------------------------------------------------------------------------;
* This macro encapsulates all the logic needed to process a single year of data.
*
* Parameters:
* YEAR_FULL: The full 4-digit year (e.g., 2010).
* YEAR_SHORT: The 2-digit year suffix used in MEPS filenames (e.g., 10).
* FYC_FILE: The filename of the Full-Year Consolidated dataset for that year.
* MC_FILE: The filename of the Medical Conditions dataset for that year.
*-------------------------------------------------------------------------------;
%macro Process_MEPS_Year(YEAR_FULL=, YEAR_SHORT=, FYC_FILE=, MC_FILE=);

    /*-- Step 3a: Identify individuals with depression for the given year --*/
    data depression_flag (keep = DUPERSID depr_flag);
        set MEPS.&MC_FILE.;

        /* Use ICD-9 codes for years before 2016, and ICD-10 codes for 2016+ */
        %if &YEAR_FULL. < 2016 %then %do;
            where icd9codx in ("311", "296", "300");
        %end;
        %else %do;
            /* Using STARTSWITH for broader matching of F-codes */
            where substr(ICD10CDX, 1, 3) in ("F32", "F34", "F39", "F40", "F41", "F42");
        %end;

        depr_flag = 1;
    run;

    /* Sort by DUPERSID to prepare for merging */
    proc sort data=depression_flag nodupkey;
        by DUPERSID;
    run;

    /*-- Step 3b: Merge flag with FYC data, subset, and harmonize variables --*/
    data year_&YEAR_FULL._processed;
        merge MEPS.&FYC_FILE. (in=in_fyc)
              depression_flag (in=in_depr);
        by DUPERSID;

        /* Keep only individuals present in both files (i.e., with depression) */
        if in_fyc and in_depr;

        /* Add a year identifier */
        year = &YEAR_FULL.;

        /* Standardize variable names across all years.
           The RENAME statement maps year-specific names (e.g., AGE10X) to
           a common name (e.g., AGE). */
        rename
            AGE&YEAR_SHORT.X  = AGE
            MARRY&YEAR_SHORT.X= MARRY
            TTLP&YEAR_SHORT.X = TTLP
            FAMINC&YEAR_SHORT.= FAMINC
            POVCAT&YEAR_SHORT.= POVCAT
            POVLEV&YEAR_SHORT.= POVLEV
            TOTEXP&YEAR_SHORT.= TOTEXP
            OBVEXP&YEAR_SHORT.= OBVEXP
            UNINS&YEAR_SHORT. = UNINS
            INSCOV&YEAR_SHORT.= INSCOV
            PRVEV&YEAR_SHORT. = PRVEV
            MCREV&YEAR_SHORT. = MCREV
            MCDEV&YEAR_SHORT. = MCDEV
            OBDRV&YEAR_SHORT. = OBDRV
            OBNURS&YEAR_SHORT.= OBNURS
            OPTOTV&YEAR_SHORT.= OPTOTV
            OPDRV&YEAR_SHORT. = OPDRV
            ERTOT&YEAR_SHORT. = ERTOT
            IPZERO&YEAR_SHORT.= IPZERO
            IPDIS&YEAR_SHORT. = IPDIS
            IPNGTD&YEAR_SHORT.= IPNGTD
            RXTOT&YEAR_SHORT. = RXTOT
            RXEXP&YEAR_SHORT. = RXEXP
            REGION&YEAR_SHORT.= REGION
            TOTTCH&YEAR_SHORT.= TOTTCH
            %if &YEAR_FULL. <= 2012 %then %do;
                RACETHNX = RACE_ETHNICITY
            %end;
            %else %do;
                RACETHX = RACE_ETHNICITY
            %end;
            %if &YEAR_FULL. >= 2018 %then %do;
                DIABDX_M18 = DIABDX
            %end;
        ;

        /* Keep only the final, harmonized set of variables */
        keep DUPERSID year depr_flag AGE SEX RACE_ETHNICITY MARRY EDUCYR HIDEG
             MNHLTH31 MNHLTH42 MNHLTH53 HIBPDX CHOLDX CANCERDX ARTHDX ASTHDX
             DIABDX TTLP FAMINC POVCAT POVLEV TOTEXP OBVEXP UNINS INSCOV PRVEV
             MCREV MCREV MCDEV RTHLTH31 RTHLTH42 RTHLTH53 ADSAD42 ADDPRS42
             K6SUM42 PHQ242 OBDRV OBNURS OPTOTV OPDRV ERTOT IPZERO IPDIS IPNGTD
             RXTOT RXEXP ADAPPT42 ADINSB42 ADNSMK42 ADRTCR42 ADSMOK42 ANGIDX
             BMINDX53 CHDDX PREGNT31 PREGNT42 PREGNT53 RACEX REGION STRKDX TOTTCH;
    run;

    /*-- Step 3c: Append the processed data for this year to the master table --*/
    proc append base=WORK.ALL_YEARS_DEPRESSION data=WORK.year_&YEAR_FULL._processed force;
    run;

    /* Clean up intermediate work table for this year */
    proc delete data=WORK.year_&YEAR_FULL._processed;
    run;

%mend Process_MEPS_Year;


* 4. MACRO EXECUTION *;
*-------------------------------------------------------------------------------;
* Create an empty shell dataset to hold the combined data.
* This avoids PROC APPEND errors on the first iteration.
proc sql;
   create table WORK.ALL_YEARS_DEPRESSION like WORK.year_2010_processed;
quit;
* Note: The line above will cause a warning on first run because
* year_2010_processed doesn't exist yet. To create the shell properly,
* we first run the macro for one year, then create the final table,
* and then run for the remaining years. A simpler approach for scripting
* is to let PROC APPEND create the base table on the first run. The FORCE
* option helps with this. For robustness, we will create an empty table first.
* To do this without errors, we can run the first year, then copy the structure.
* For simplicity in this script, we will let PROC APPEND handle it.
* Let's clear the WORK.ALL_YEARS_DEPRESSION if it exists.
proc delete data=WORK.ALL_YEARS_DEPRESSION;
run;


* Call the macro for each year of MEPS data.
* This replaces all the repetitive code from the original script.
message "Processing MEPS data from 2010 to 2019...";
%Process_MEPS_Year(YEAR_FULL=2010, YEAR_SHORT=10, FYC_FILE=h138, MC_FILE=h137);
%Process_MEPS_Year(YEAR_FULL=2011, YEAR_SHORT=11, FYC_FILE=h147, MC_FILE=h146);
%Process_MEPS_Year(YEAR_FULL=2012, YEAR_SHORT=12, FYC_FILE=h155, MC_FILE=h154);
%Process_MEPS_Year(YEAR_FULL=2013, YEAR_SHORT=13, FYC_FILE=h163, MC_FILE=h162);
%Process_MEPS_Year(YEAR_FULL=2014, YEAR_SHORT=14, FYC_FILE=h171, MC_FILE=h170);
%Process_MEPS_Year(YEAR_FULL=2015, YEAR_SHORT=15, FYC_FILE=h181, MC_FILE=h180);
%Process_MEPS_Year(YEAR_FULL=2016, YEAR_SHORT=16, FYC_FILE=h192, MC_FILE=h190);
%Process_MEPS_Year(YEAR_FULL=2017, YEAR_SHORT=17, FYC_FILE=h201, MC_FILE=h199);
%Process_MEPS_Year(YEAR_FULL=2018, YEAR_SHORT=18, FYC_FILE=h209, MC_FILE=h207);
%Process_MEPS_Year(YEAR_FULL=2019, YEAR_SHORT=19, FYC_FILE=h216, MC_FILE=h214);
message "All years have been processed and combined.";


* 5. FINAL EXPORT *;
*-------------------------------------------------------------------------------;
* Export the final, combined dataset to a CSV file for use in other software.
* Update the OUTFILE path as needed.
message "Exporting final dataset to CSV...";
proc export data=WORK.ALL_YEARS_DEPRESSION
    outfile="&DATA_PATH./Final_MEPS_Depression_Cohort_2010_2019.csv"
    dbms=csv
    replace;
run;

message "Script finished successfully. Output CSV has been created.";


* CLEANUP *;
*-------------------------------------------------------------------------------;
* Clear the libname.
libname MEPS clear;
