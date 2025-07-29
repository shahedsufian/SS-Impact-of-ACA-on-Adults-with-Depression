/*******************************************************************************
*
* Stata Do-File: Difference-in-Differences Analysis of ACA Expansion
*
* Purpose:
* This script performs a Difference-in-Differences (DID) and Triple-Differences
* (DDD) analysis to evaluate the impact of the Affordable Care Act (ACA) on
* various outcomes for a population with depression. It uses survey-weighted
* data to generate descriptive statistics and run several regression models,
* including OLS, GLM, and Two-Part models.
*
* Key Steps:
* 1. Setup: Initializes Stata environment, sets file paths, and starts a log.
* 2. Data Preparation: Creates key analysis variables (DID/DDD terms, dummies).
* 3. Survey Design: Sets the survey design using `svyset` for proper inference.
* 4. Define Globals: Creates global macros for outcomes and controls to reduce
* code repetition.
* 5. Descriptive Statistics: Generates survey-weighted means and tabulations.
* 6. Main DID Analysis: Uses a loop to run OLS, GLM, and Two-Part models for
* each outcome variable.
* 7. Triple-Difference (DDD) Analysis: Uses a nested loop to run models for
* subgroups (Hispanic, Black) for each outcome.
* 8. Cleanup: Closes the log file.
*
* Required Data:
* A Stata dataset (`.dta`) containing the prepared MEPS data should be loaded.
* This script assumes the data is already in memory.
*
*******************************************************************************/


* 1. SETUP & CONFIGURATION
*-------------------------------------------------------------------------------

* Clear memory and close any open log files
clear all
capture log close

* Prevent Stata from pausing after each screen of output
set more off

* --- IMPORTANT: UPDATE FILE PATHS ---
* Set the working directory to your project folder.
* cd "C:\path\to\your\project\folder"

* Start a log file to record all commands and output.
* log using "meps_did_analysis_log.smcl", replace

* Load your final, combined MEPS dataset.
* use "Final_MEPS_Depression_Cohort_2010_2019.dta", clear


* 2. DATA PREPARATION & VARIABLE CREATION
*-------------------------------------------------------------------------------
* Note on weights: If you need to scale weights (e.g., for panel analysis),
* you would do it here. The original code was commented out, so we leave it as a note.
* * gen nwght = PERWT10F / 10  // Example of scaling by number of years

* Create the main Difference-in-Differences (DID) interaction term
* dd = 1 for the treatment group in the post-ACA period
generate dd = TREATMENT * PRE_POST
label var dd "DID Interaction (TREATMENT * PRE_POST)"

* Create Triple-Difference (DDD) interaction terms for race/ethnicity subgroups
* Hispanic
generate DDD_H = TREATMENT * PRE_POST * HISPANIC
generate H_PERIOD = PRE_POST * HISPANIC
generate H_TREATMENT = TREATMENT * HISPANIC
label var DDD_H "DDD Interaction (Hispanic)"

* Black
generate DDD_B = TREATMENT * PRE_POST * BLACK
generate B_PERIOD = PRE_POST * BLACK
generate B_TREATMENT = TREATMENT * BLACK
label var DDD_B "DDD Interaction (Black)"

* Create numeric factor variables from string/categorical variables for use in models
* The `encode` command creates a new numeric variable with value labels.
tostring REGION10, replace // Ensure REGION is a string before encoding
encode RACEX, generate(RACE_NUM)
encode HIDEG, generate(HIDEG_NUM)
encode MNHLTH42, generate(MNHLTH42_NUM)
encode POVCAT10, generate(POVCAT10_NUM)
encode RTHLTH42, generate(RTHLTH42_NUM)
encode REGION10, generate(REGION_NUM)

* Create binary dummy variables for whether an expenditure is non-zero
* This is useful for descriptive stats and the first part of two-part models.
generate EXPENSE_0 = (TOTEXP10 > 0) if TOTEXP10 < .
generate OFFICE_0  = (OBVEXP10 > 0) if OBVEXP10 < .
generate CHARGES_0 = (TOTTCH10 > 0) if TOTTCH10 < .
generate RXEXP_0   = (RXEXP10 > 0)  if RXEXP10 < .


* 3. SURVEY DESIGN DECLARATION
*-------------------------------------------------------------------------------
* Declare the survey design of the MEPS data. This is crucial for obtaining
* correct standard errors and point estimates.
* Assumes PERWT10F is the person-level weight, VARPSU is the PSU, and VARSTR is the stratum.
* These variable names may need to be updated depending on your final dataset.
svyset VARPSU [pw=PERWT10F], singleunit(certainty) strata(VARSTR)


* 4. DEFINE GLOBAL MACROS FOR EFFICIENT MODELING
*-------------------------------------------------------------------------------
* Define a global macro with the list of outcome variables.
* This allows us to loop through models instead of repeating code.
global OUTCOMES "TOTEXP10 OBVEXP10 TOTTCH10 RXEXP10"

* Define a global macro with the core list of control variables.
global CONTROLS "SEX i.RACE_NUM MARRY10X i.HIDEG_NUM i.POVCAT10_NUM UNINS10 ///
                 PRVEV10 MCREV10 MCDEV10 i.MNHLTH42_NUM i.RTHLTH42_NUM ///
                 HIBPDX CHOLDX CANCERDX ARTHDX ASTHDX DIABDX ///
                 ANGIDX CHDDX i.REGION_NUM"


* 5. DESCRIPTIVE STATISTICS
*-------------------------------------------------------------------------------
display "--- Generating Descriptive Statistics ---"

* Calculate survey-weighted means for continuous outcomes by group
foreach var of varlist TOTEXP10 OBVEXP10 TOTTCH10 RXEXP10 {
    display "Mean of `var' by Treatment and Period"
    svy: mean `var', over(TREATMENT PRE_POST)
}

* Calculate survey-weighted means for binary expenditure dummies by group
foreach var of varlist EXPENSE_0 OFFICE_0 CHARGES_0 RXEXP_0 {
    display "Mean of `var' by Treatment and Period"
    svy: mean `var', over(TREATMENT PRE_POST)
}

* Calculate survey-weighted means for key demographic and health variables
foreach var of varlist SEX MARRY10X UNINS10 PRVEV10 MCREV10 MCDEV10 HIBPDX ///
                       CHOLDX CANCERDX ARTHDX ASTHDX DIABDX ANGIDX CHDDX {
    display "Mean of `var' by Treatment and Period"
    svy: mean `var', over(TREATMENT PRE_POST)
}

* Generate survey-weighted cross-tabulations for categorical variables
foreach var of varlist RACEX HIDEG POVCAT10 MNHLTH42 RTHLTH42 {
    display "Tabulation of `var' by Treatment, Pre-Period"
    svy: tabulate `var' TREATMENT if PRE_POST == 0, column
    display "Tabulation of `var' by Treatment, Post-Period"
    svy: tabulate `var' TREATMENT if PRE_POST == 1, column
}


* 6. MAIN DID ANALYSIS (OLS, GLM, TWO-PART MODELS)
*-------------------------------------------------------------------------------
display "--- Running Main DID Models for All Outcomes ---"

* Loop through each outcome variable defined in the global macro
foreach outcome of global OUTCOMES {

    display "****************************************************************"
    display "MODELING OUTCOME: `outcome'"
    display "****************************************************************"

    * --- OLS Model ---
    display "--- `outcome': OLS Regression ---"
    svy: reg `outcome' TREATMENT PRE_POST dd ${CONTROLS}

    * --- GLM Model (Gamma with Log Link) ---
    display "--- `outcome': GLM (Gamma, Log Link) ---"
    svy: glm `outcome' TREATMENT PRE_POST dd ${CONTROLS}, family(gamma) link(log) eform
    * margins, dydx(*) // Optional: Uncomment to see marginal effects

    * --- Two-Part Model ---
    display "--- `outcome': Two-Part Model (Probit + GLM) ---"
    svy: twopm `outcome' TREATMENT PRE_POST dd ${CONTROLS}, f(probit) s(glm, family(gamma) link(log))
    * margins, dydx(*) // Optional: Uncomment to see marginal effects
}


* 7. TRIPLE-DIFFERENCE (DDD) ANALYSIS
*-------------------------------------------------------------------------------
display "--- Running Triple-Difference (DDD) Models for Subgroups ---"

* Loop through each subgroup (Hispanic, Black)
foreach subgroup in "H" "B" {

    if "`subgroup'" == "H" {
        local sub_name "Hispanic"
    }
    if "`subgroup'" == "B" {
        local sub_name "Black"
    }

    display "****************************************************************"
    display "DDD ANALYSIS FOR SUBGROUP: `sub_name'"
    display "****************************************************************"

    * Loop through each outcome for the current subgroup
    foreach outcome of global OUTCOMES {

        display "--- DDD for `outcome' ---"

        * --- OLS Model ---
        svy: reg `outcome' TREATMENT PRE_POST dd `subgroup'_PERIOD DDD_`subgroup' `subgroup'_TREATMENT ${CONTROLS}

        * --- GLM Model ---
        svy: glm `outcome' TREATMENT PRE_POST dd `subgroup'_PERIOD DDD_`subgroup' `subgroup'_TREATMENT ${CONTROLS}, family(gamma) link(log) eform

        * --- Two-Part Model ---
        svy: twopm `outcome' TREATMENT PRE_POST dd `subgroup'_PERIOD DDD_`subgroup' `subgroup'_TREATMENT ${CONTROLS}, f(probit) s(glm, family(gamma) link(log))
    }
}


* 8. CLEANUP
*-------------------------------------------------------------------------------
* Close the log file
log close
display "Analysis complete. Log file saved."

* End of do-file
