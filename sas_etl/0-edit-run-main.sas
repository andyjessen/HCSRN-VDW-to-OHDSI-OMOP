/*********************************************
* John Weeks
* Kaiser Permanente Washington Health Research Institute
* (206) 287-2711
* John.M.Weeks@kp.org
*
*
*
* Purpose:: Populates variables with user's parameters
*            and runs the translation process
* Date Created:: 2019-09-05
*********************************************/

/**************************** EDIT SECTION *************************/
/* Save this file as 0-run-main.sas and then edit values that are in brackets <> */
/* Include your Standard Variables for your local VDW and RCM Standard Variables */
%include <"Place Path to VDW Connections and Variables Here">;

/* Root location of folder HCSRN VDW to OHDSI OMOP */
%let root=<location of cloned HCSRN-VDW-to-OHDSI-OMOP project>;

/*
*  !!! Be sure to update the file "&root./HCSRN-VDW-to-OHDSI-OMOP/rcm_vdw_vars.sas" 
*  The file should point back to your local VDW Variables ... It also allows you to
*  Substitute a local database stored version of the OMOP Vocabulary and
*  Research Code Management(RCM) tables.  They default to locally created sas data files !!!
*/
/**************************** END EDIT SECTION *************************/



/* Some Default Options Settings Adjust if necessary */
options
  linesize  = 150
  msglevel  = i
  formchar  = '|-++++++++++=|-/|<>*'
  dsoptions = note2err 
  nocenter
  noovp
  extendobscounter = no
;


/* libraries for transformation code */
%let rt=&root.\HCSRN-VDW-to-OHDSI-OMOP\;

libname etl "&rt.sas_etl";
libname dat "&rt.sas_dat";
libname omop "&rt.omop_files";
libname vocab "&rt.omop_vocab";

/* Run Build */
/* Picks up OMOP Vocabulary CSV files produced by Athena and creates or merges into OMOP Vocab SAS datafiles */
  %include "&rt./sas_etl/01-merge-omop-vocab.sas";
/* Load VDW Codebucket by joining data from VDW Standard Variables and Standard Codes from OMOP Vocabulary */ 
  %include "&rt./sas_etl/02-load-VDW-CB.sas";
/* Creates SAS datafiles that represent the code relationships that translate from VDW Codes to OMOP Codes */
  %include "&rt./sas_etl/03-load-RCM.sas";
/* An abstraction layer that enables the programmer to choose the source for the VDW, OMOP Vocabulary and RCM */
  %include "&rt./sas_etl/rcm_vdw_vars.sas";
/* Creates the Primary OMOP Primary Tables as SAS data files and stores in the omop_files folder */
  %include "&rt./sas_etl/1-load-OMOP.sas";
/* Creates the OMOP Era Tables */
  %include "&rt./sas_etl/2-load-OMOP-Era.sas";
