/*********************************************
* John Weeks
* Kaiser Permanente Washington Health Research Institute
* (206) 287-2711
* John.M.Weeks@kp.org
*
*
*
* Purpose:: Builds SAS data files that represent an OMOP-CDM based on a cohort of patients
* Date Created:: 2019-05-23
*********************************************/


* populates facility location information into omop.location;
proc sql;
  create table omop.location as
  select monotonic() as location_id,
    left(fa.street_address) as address_1,
    '' as address_2,
    fa.city,
    fa.state,
    fa.zip,
    '' as county,
    fa.facility_code as location_source_value
  from &_vdw_facility as fa
  order by fa.facility_code
  ;
quit;


* populate omop.care_site;
proc sql;
  create table omop.location_pos_bridge as
    select distinct
      ue.facility_code as care_site_source_value,
      ue.enctype||'_'||ue.encounter_subtype as enctype_subtype
    from &_vdw_utilization ue
  ;
quit;


* create a table with distinct care sites;
* enter local field for care_site_name if available;
proc sql;
  create table unq_care_site as
  select distinct
    loc.location_id,  
    '' as care_site_name,
    ps.omop_code_id as place_of_service_concept_id,
    ue.care_site_source_value,
    ps.vdw_code as place_of_service_source_value
  from omop.location_pos_bridge ue
  inner join &_vdw_facility fa
  on fa.facility_code = ue.care_site_source_value
  inner join &_rcm_pos ps
  on ue.enctype_subtype = ps.vdw_code
  inner join omop.location loc 
  on loc.location_source_value = ue.care_site_source_value 
  where fa.facility_code ne '~~~~~~' 
  ;
quit;


* provide an id onto each distinct care site;
proc sql;
  create table omop.care_site as
  select
    monotonic() as care_site_id,
    cs.*
  from work.unq_care_site as cs
  ;
quit;


* populate omop.provider;
* enter local value for npi if available;
proc sql;
  create table unq_provider as
  select distinct
    '' as provider_name,
    '' as npi,
    '' as DEA,
    sp.omop_code_id as specialty_concept_id,
    '' as care_site_id,
    pe.provider_birth_year as year_of_birth,
    gn.omop_code_id as gender_concept_id,
    pe.provider as provider_source_value,
    sp.vdw_code as specialty_source_value,
    0 as specialty_source_concept_id,
    gn.vdw_code as gender_source_value,
    0 as gender_source_concept_id
  from
    &_vdw_provider_specialty pe
  left join &_rcm_physician_specialty sp
    on pe.specialty = sp.vdw_code
     and sp.vdw_code ne 'NO_MAP'
  left join &_rcm_gender gn
    on pe.provider_gender = gn.vdw_code
    where pe.provider ne '~~~~~~'
;
quit;

proc sql;
  create table omop.provider as
    select monotonic() as provider_id, unp.* from work.unq_provider unp;
quit;



*populate omop.person; 
proc sql outobs=100;
  create table omop.person as
  select
    monotonic() as person_id,
    lug.omop_code_id as gender_concept_id,
    year(dem.birth_date) as year_of_birth,
    month(dem.birth_date) as month_of_birth,
    day(dem.birth_date) as day_of_birth,
    dem.birth_date as birth_datetime,
    coalesce(lur.omop_code_id, 8552) as race_concept_id,
    case dem.hispanic
      when 'Y' then let.omop_code_id
      when 'N' then let.omop_code_id
      when 'U' then 0
    end as ethnicity_concept_id,
    0 as location_id,
    0 as provider_id,
    0 as care_site_id,
    dem.mrn as person_source_value,
    dem.sex_admin as gender_source_value,
    0 as gender_source_concept_id,
    dem.race1 as race_source_value,
    0 as race_source_concept_id,
    dem.hispanic as ethnicity_source_value,
    0 as ethnicity_source_concept_id
  from &_vdw_demographic dem
  left join &_rcm_gender lug
  on lug.vdw_code = dem.sex_admin
  left join &_rcm_race lur
  on lur.vdw_code = dem.race1
  left join &_rcm_ethnicity let
  on let.vdw_code = dem.hispanic
;
quit;


* populates omop.visit_occurance;
proc sql;
  create table omop.visit_occurrence as
    select
    monotonic() as visit_occurrence_id,
    pn.person_id,
    vi.omop_code_id as visit_concept_id,
    ute.adate as visit_start_date,
    ute.atime as visit_start_datetime,
    ute.ddate as visit_end_date,
    ute.dtime as visit_end_datetime,
    vt.omop_code_id as visit_type_concept_id,  
    pr.provider_id, 
    cs.care_site_id, 
    ute.enc_id as visit_source_value,
    0 as visit_source_concept_id,
    las.omop_code_id as admitting_source_concept_id,  
    las.vdw_code as admitting_source_value,  
    lds.omop_code_id as discharge_to_concept_id,  
    lds.vdw_code as discharge_to_source_value,  
    0 as preceding_visit_occurrence_id
  from
    &_vdw_utilization ute
    inner join omop.person pn
    on ute.mrn = pn.person_source_value
    inner join omop.provider pr 
    on ute.provider = pr.provider_source_value 
    inner join omop.care_site cs 
    on ute.facility_code = cs.care_site_source_value 
    and ute.enctype = substr(cs.place_of_service_source_value, 1, 2)
    and ute.encounter_subtype = substr(cs.place_of_service_source_value, 4, 2)
    inner join &_rcm_enctype vi 
    on ute.enctype = vi.vdw_code 
    left join &_rcm_admit_source vt   
    on ute.source_data = vt.vdw_code  
    left join &_rcm_admit_source las  
    on las.vdw_code = ute.admitting_source  
    left join &_rcm_discharge_status lds  
    on lds.vdw_code = ute.discharge_status  
 ;
quit;


*populate omop.condition_occurrence;
* use local dx end_date and time if available;
proc sql;
  create table omop.condition_occurrence as
  select
    monotonic() as condition_occurrence_id,
    pn.person_id,
    coalesce(ldx.omop_code_id, 0) as condition_concept_id,
    put(dx.adate, date.)  as condition_start_date,
    put(dx.adate, datetime.) as condition_start_datetime,
    put(vo.visit_end_date, date.) as condition_end_date,
    put(vo.visit_end_datetime, datetime.) as condition_end_datetime,
    case when dx.primary_dx = 'P'
      then 44786627
      when dx.primary_dx = 'S'
      then 44786628
      else 0
    end as condition_type_concept_id,
    '' as stop_reason,
    pr.provider_id,
    vo.visit_occurrence_id,
    dx.dx as condition_source_value,
    ldx.vdw_code_id as condition_source_concept_id,
    '' as condition_status_source_value,
    4033240 as condition_status_concept_id
  from &_vdw_dx dx
  inner join omop.person pn
  on pn.person_source_value = dx.mrn
  inner join omop.visit_occurrence vo
  on dx.enc_id = vo.visit_source_value
  left join omop.provider pr
  on dx.diagprovider = pr.provider_source_value
  left join &_rcm_diagnosis ldx
  on dx.dx = ldx.vdw_code
  ;
quit;



*populate omop.procedure_occurrence;
proc sql;
  create table omop.procedure_occurrence as
  SELECT
    monotonic() as procedure_occurrence_id
    , procs.*
  FROM (
    SELECT DISTINCT
       pn.person_id
      ,pxt.omop_code_id as procedure_concept_id
      ,px.procdate as procedure_date
      ,px.procdate as procedure_datetime format=datetime.
      ,38000266 as procedure_type_concept_id
      ,pxm.omop_code_id as modifier_concept_id
      ,0 as quantity
      ,pr.provider_id
      ,vo.visit_occurrence_id
      ,px.px as procedure_source_value
      ,0 as procedure_source_concept_id
      ,'' as qualifier_source_value
    FROM
    &_vdw_px px
    inner join omop.person pn
     on pn.person_source_value = px.mrn
    inner join omop.visit_occurrence vo
     on px.enc_id = vo.visit_source_value
    left join omop.provider pr
     on px.performingprovider = pr.provider_source_value
    inner join &_rcm_procedure pxt
     on pxt.vdw_code = px.px
    left join &_rcm_procedure pxm
     on pxm.vdw_code = px.cptmod1
  ) procs
;
quit;


*populate omop.death; 
proc sql;
  create table omop.death as
  select distinct
    monotonic() as death_id,
    pe.person_id,
    dt.deathdt as death_date,
    put(dt.deathdt, datetime.) as death_datetime,
    dtht.omop_code_id as death_type_concept_id,
    cod.omop_code_id as cause_concept_id,
    cod.vdw_code as cause_source_value,
    0 as cause_source_concept_id
  from omop.person pe
  inner join &_vdw_death dt
   on pe.person_source_value = dt.mrn
  left join &_vdw_cause_of_death cc
   on cc.mrn = dt.mrn
  left join &_rcm_cod cod
   on cc.cod = cod.vdw_code
  left join &_rcm_deathtype dtht
   on dt.source_list = dtht.vdw_code
;
quit;



*populate omop.drug_exposure;
proc sql;
  create table omop.drug_exposure as
  select
    monotonic() as drug_exposure_id
    ,pn.person_id
    ,coalesce (ndc.omop_code_id, 0) as drug_concept_id
    ,rx.rxdate as drug_exposure_start_date
    ,put(rx.rxdate, datetime.) as drug_exposure_start_datetime
    ,rx.rxdate as drug_exposure_end_date
    ,put(rx.rxdate, datetime.) as drug_exposure_end_datetime
    ,'' as verbatim_end_date
    ,ndc.omop_cd_type as drug_type_concept_id
    ,'' as stop_reason
    ,case rx.rxfill
      when 'I' then 0
      when 'R' then 1
      else 0
     end as refills
    ,rx.rxamt as quantity
    ,rx.rxsup as days_supply
    ,'' as sig
    ,0 as route_concept_id
    ,0 as lot_number
    ,pr.provider_id
    ,0 as visit_occurrence_id
    ,rx.ndc as drug_source_value
    ,0 as drug_source_concept_id
    ,rx.source as route_source_value
    ,'' as dose_unit_source_value
  from
    &_vdw_rx rx
    inner join omop.person pn
    on pn.person_source_value = rx.mrn
    left join omop.provider pr
    on pr.provider_source_value = rx.rxmd
    left join &_rcm_ndc ndc
    on rx.ndc = ndc.vdw_code
  ;
quit;



/* populate omop.drug_strength */
/* Rx fill information */


/* populate omop.dose_era */
/* period of time that a specific dose was being give for a specific drug at a specific dosage */

/*
* populate omop.specimen ;
proc sql;
  create table omop.specimen as
  SELECT
    monotonic() as specimen_id
    ,pn.person_id
    ,0 as specimen_concept_id
    ,0 as specimen_type_concept_id
    ,put(tm.dxdate, date.) as specimen_date
    ,put(tm.dxdate, datetime.) as specimen_datetime
    , as quantity
    ,cp.concept_id as unit_concept_id
    ,0 as anatomic_site_concept_id
    ,0 as disease_status_concept_id
    , as specimen_source_id
    , as specimen_source_value
    , as unit_source_value
    ,tm.ICDOSITE as anatomic_site_source_value
    , as disease_status_source_value
  FROM &_vdw_tumor tm
    INNER JOIN omop.person pn
    on lb.mrn = pn.person_source_value
    left join &_omop_concept cp
    on upcase(cp.concept_code) = lb.std_result_unit
    and lb.std_result_unit is not null
  ;
quit;
*/


* populate omop.specimen ;
proc sql;
  create table omop.specimen as
  SELECT
    monotonic() as specimen_id
    ,pn.person_id
    ,0 as specimen_concept_id
    ,0 as specimen_type_concept_id
    ,put(lb.lab_dt, date.) as specimen_date
    ,put(lb.lab_tm, datetime.) as specimen_datetime
    ,1 as quantity
    ,cp.concept_id as unit_concept_id
    ,0 as anatomic_site_concept_id
    ,0 as disease_status_concept_id
    ,lb.specimen_id as specimen_source_id
    ,lb.specimen_source as specimen_source_value
    ,lb.std_result_unit as unit_source_value
    ,lb.specimen_source as anatomic_site_source_value
    ,lb.result_c as disease_status_source_value
  FROM &_vdw_lab lb
    INNER JOIN omop.person pn
    on lb.mrn = pn.person_source_value
    left join &_omop_concept cp
    on upcase(cp.concept_code) = lb.std_result_unit
    and lb.std_result_unit is not null
  ;
quit;



/* populate omop.fact_relationship */


/* populate omop.payer_plan_period */

proc sql;
  create table omop.payer_plan_period as
  SELECT
    0 as payer_plan_period_id
    ,pn.person_id
    ,en.enr_start as payer_plan_period_start_date
    ,en.enr_end as payer_plan_period_end_date
    ,en.mainnet as payer_source_value
    ,'' as plan_source_value
    ,'' as family_source_value
  FROM &_vdw_enroll en
  INNER JOIN omop.person pn
    on pn.person_source_value = en.mrn
   ;
quit;



 /* populate omop.observation **Would Need Social_History */
/* The OBSERVATION table captures clinical facts about a Person 
  obtained in the context of examination, questioning or a procedure.
  Any data that cannot be represented by any other domains, such as social and lifestyle facts, 
  medical history, family history, etc. are recorded here.
*/


 /* populate omop.observation_period */
proc sql;
  create table omop.observation_period as
  SELECT
    monotonic() as observation_period_id,
    opq.*, 44814725 as period_type_concept_id
  FROM
  (
    SELECT
      person.person_id AS person_id,
      MIN(visit_occurrence.visit_start_date) AS observation_period_start_date,
      MIN(visit_occurrence.visit_start_datetime) AS observation_period_start_dttm,
      MAX(visit_occurrence.visit_end_date) AS observation_period_end_date,
      MAX(visit_occurrence.visit_end_datetime) AS observation_period_end_dttm
    FROM  omop.person 
    LEFT JOIN omop.visit_occurrence
    ON person.person_id = visit_occurrence.person_id
    GROUP BY person.person_id
  ) opq
  ;
quit;


 /* populate omop.measurement  ** Would still need to add Vital Signs */
/*
  The MEASUREMENT table contains records of Measurement, i.e. structured values (numerical 
  or categorical) obtained through systematic and standardized examination or testing of 
  a Person or Person's sample. The MEASUREMENT table contains both orders and results of 
  such Measurements as laboratory tests, vital signs, quantitative findings from pathology 
  reports, etc.
*/

proc sql;
  create table tmp_measurement_labs as
  select DISTINCT
    pn.person_id
    , ml.omop_code_id as measurement_concept_id
    , CASE when lr.lab_dt ne . 
          then put(lr.lab_dt, date.)
          else ''
        end as measurement_date
    , case when put(lr.lab_tm, time.) ne '' then 1
    else 0
    end as time_flag
    , put(lr.lab_dt, date.)||' '||put(lr.lab_tm, time.) as measurement_datetime
    , 44818702 as measurement_type_concept_id
    , 0 as operator_concept_id
    , put(input(trim(lr.result_c), float4.), float4.) as value_as_number
    , 0 as value_as_concept_id
    , 0 as unit_concept_id
    , input( trim(lr.normal_low_c), float4.) as range_low
    , input( trim(lr.normal_high_c), float4.) as range_high
    , pv.provider_id
    , vo.visit_occurrence_id
    , lr.loinc as measurement_source_value
    , ml.omop_code_id as measurement_source_concept_id
    , lr.result_unit as unit_source_value
    , put(input(lr.result_c, 20.), 20.) as value_source_value
  from &_vdw_lab lr
  inner join omop.person pn
  on lr.mrn = pn.person_source_value
  inner join omop.provider pv
  on lr.order_prov = pv.provider_source_value
  left join &_rcm_lab_loinc ml
  on lr.loinc = ml.vdw_code
  left join omop.visit_occurrence vo
  on (vo.person_id = pn.person_id
  and put(lr.lab_dt, date.) = put(vo.visit_start_date, date.)
  and vo.provider_id = pv.provider_id)
  where lr.lab_dt is not null
  and lr.lab_dt ne .
  ;
quit;


proc sql;
  create table tmp_meas_vitals_ht_est as
  select DISTINCT
    pn.person_id
    ,3035463 as measurement_concept_id
    ,vs.measure_date as measurement_date
    ,put(vs.measure_date, date.)||' '||put(vs.measure_time, time.) as measurement_datetime
     ,44818701 as measurement_type_concept_id 
    ,4172703 as operator_concept_id
    ,put(vs.ht_estimate, float4.) as value_as_number
    ,0 as value_as_concept_id
    ,9330 as unit_concept_id
    ,0 as range_low
    ,0 as range_high
    ,vo.provider_id
    ,vo.visit_occurrence_id
    ,'8301-4' as measurement_source_value
    ,3023540 as measurement_source_concept_id
    ,'[in_us]' as unit_source_value
    ,put(vs.ht_estimate, 20.) as value_source_value
  FROM &_vdw_vitalsigns vs
    INNER JOIN omop.person pn
    ON vs.mrn = pn.person_source_value
    LEFT JOIN omop.visit_occurrence vo
    ON vs.enc_id = vo.visit_source_value
  WHERE vs.ht_estimate ne .
  ;
quit;


proc sql;
  create table tmp_meas_vitals_ht as
  select DISTINCT
    pn.person_id
    ,3023540 as measurement_concept_id
    ,vs.measure_date as measurement_date
    ,put(vs.measure_date, date.)||' '||put(vs.measure_time, time.) as measurement_datetime
    ,44818701 as measurement_type_concept_id 
    ,4172703 as operator_concept_id
    ,put(vs.ht, float4.) as value_as_number
    ,0 as value_as_concept_id
    ,9330 as unit_concept_id 
    ,0 as range_low
    ,0 as range_high
    ,vo.provider_id
    ,vo.visit_occurrence_id
    ,'3137-7' as measurement_source_value
    ,3023540 as measurement_source_concept_id
    ,'[in_us]' as unit_source_value
    ,put(vs.ht, 20.) as value_source_value
  FROM &_vdw_vitalsigns vs 
    INNER JOIN omop.person pn
    ON vs.mrn = pn.person_source_value
    LEFT JOIN omop.visit_occurrence vo
    ON vs.enc_id = vo.visit_source_value
  WHERE vs.ht ne .
  ;
quit;


proc sql;
  create table tmp_meas_vitals_wt as
  select DISTINCT
    pn.person_id
    ,3025315 as measurement_concept_id
    ,vs.measure_date as measurement_date
    ,put(vs.measure_date, date.)||' '||put(vs.measure_time, time.) as measurement_datetime
    ,44818701 as measurement_type_concept_id 
    ,4172703 as operator_concept_id
    ,put(vs.wt, float4.) as value_as_number
    ,0 as value_as_concept_id
    ,8739 as unit_concept_id
    ,0 as range_low
    ,0 as range_high
    ,vo.provider_id
    ,vo.visit_occurrence_id
    ,'29463-7' as measurement_source_value
    ,3023540 as measurement_source_concept_id
    ,'[lb_us]' as unit_source_value
    ,put(vs.wt, 20.) as value_source_value
  FROM &_vdw_vitalsigns vs 
    INNER JOIN omop.person pn
    ON vs.mrn = pn.person_source_value
    LEFT JOIN omop.visit_occurrence vo
    ON vs.enc_id = vo.visit_source_value
  WHERE vs.wt ne .
  ;
quit;


proc sql;
  create table tmp_meas_vitals_wt_est as
  select DISTINCT
    pn.person_id
    ,3026600 as measurement_concept_id
    ,vs.measure_date as measurement_date
    ,put(vs.measure_date, date.)||' '||put(vs.measure_time, time.) as measurement_datetime
    ,44818701 as measurement_type_concept_id
    ,4172703 as operator_concept_id
    ,put(vs.wt_estimate, float4.) as value_as_number
    ,0 as value_as_concept_id
    ,8739 as unit_concept_id
    ,0 as range_low
    ,0 as range_high
    ,vo.provider_id
    ,vo.visit_occurrence_id
    ,'8335-2' as measurement_source_value
    ,3023540 as measurement_source_concept_id
    ,'[lb_us]' as unit_source_value
    ,put(vs.wt_estimate, 20.) as value_source_value
  FROM &_vdw_vitalsigns vs 
    INNER JOIN omop.person pn
    ON vs.mrn = pn.person_source_value
    LEFT JOIN omop.visit_occurrence vo
    ON vs.enc_id = vo.visit_source_value
  WHERE vs.wt_estimate ne .
  ;
quit;


proc sql;
  create table tmp_meas_vitals_bmi as
  select DISTINCT
    pn.person_id
    ,3038553 as measurement_concept_id
    ,vs.measure_date as measurement_date
    ,put(vs.measure_date, date.)||' '||put(vs.measure_time, time.) as measurement_datetime
    ,44818701 as measurement_type_concept_id
    ,4172703 as operator_concept_id
    ,put(vs.bmi, float4.) as value_as_number
    ,0 as value_as_concept_id
    ,8554 as unit_concept_id
    ,0 as range_low
    ,0 as range_high
    ,vo.provider_id
    ,vo.visit_occurrence_id
    ,'39156-5' as measurement_source_value
    ,3038553 as measurement_source_concept_id
    ,'%' as unit_source_value
    ,put(vs.bmi, 20.) as value_source_value
  FROM &_vdw_vitalsigns vs 
    INNER JOIN omop.person pn
    ON vs.mrn = pn.person_source_value
    LEFT JOIN omop.visit_occurrence vo
    ON vs.enc_id = vo.visit_source_value
  WHERE vs.bmi ne .
    ;
quit;


proc sql;
  create table tmp_meas_vitals_bpd as
  select DISTINCT
    pn.person_id
    ,3012888 as measurement_concept_id
    ,vs.measure_date as measurement_date
    ,put(vs.measure_date, date.)||' '||put(vs.measure_time, time.) as measurement_datetime
    ,44818701 as measurement_type_concept_id
    ,4172703 as operator_concept_id
    ,put(vs.diastolic, float4.) as value_as_number
    ,0 as value_as_concept_id
    ,8876 as unit_concept_id
    ,0 as range_low
    ,0 as range_high
    ,vo.provider_id
    ,vo.visit_occurrence_id
    ,'8462-4' as measurement_source_value
    ,3012888 as measurement_source_concept_id
    ,'mm[Hg]' as unit_source_value
    ,put(vs.diastolic, 20.) as value_source_value
  FROM &_vdw_vitalsigns vs 
    INNER JOIN omop.person pn
    ON vs.mrn = pn.person_source_value
    LEFT JOIN omop.visit_occurrence vo
    ON vs.enc_id = vo.visit_source_value
  WHERE vs.diastolic ne .
  ;
quit;



proc sql;
  create table tmp_meas_vitals_bps as
  select DISTINCT
    pn.person_id
    ,3004249 as measurement_concept_id
    ,vs.measure_date as measurement_date
    ,put(vs.measure_date, date.)||' '||put(vs.measure_time, time.) as measurement_datetime
    ,44818701 as measurement_type_concept_id
    ,4172703 as operator_concept_id
    ,put(vs.systolic, float4.) as value_as_number
    ,0 as value_as_concept_id
    ,8876 as unit_concept_id
    ,0 as range_low
    ,0 as range_high
    ,vo.provider_id
    ,vo.visit_occurrence_id
    ,'8480-6' as measurement_source_value
    ,3004249 as measurement_source_concept_id
    ,'mm[Hg]' as unit_source_value
    ,put(vs.systolic, 20.) as value_source_value
  FROM &_vdw_vitalsigns vs 
    INNER JOIN omop.person pn
    ON vs.mrn = pn.person_source_value
    LEFT JOIN omop.visit_occurrence vo
    ON vs.enc_id = vo.visit_source_value
  WHERE vs.systolic ne .
  ;
quit;


proc sql;
  create table tmp_meas_vitals_pulse as
  select DISTINCT
    pn.person_id
    ,3027018 as measurement_concept_id
    ,vs.measure_date as measurement_date
    ,put(vs.measure_date, date.)||' '||put(vs.measure_time, time.) as measurement_datetime
    ,44818701 as measurement_type_concept_id
    ,4172703 as operator_concept_id
    ,put(input(vs.pulse_raw, 20.), float4.) as value_as_number
    ,0 as value_as_concept_id
    ,8541 as unit_concept_id
    ,0 as range_low
    ,0 as range_high
    ,vo.provider_id
    ,vo.visit_occurrence_id
    ,'8867-4' as measurement_source_value
    ,3027018 as measurement_source_concept_id
    ,'{beats}/min' as unit_source_value
    ,put(input(vs.pulse_raw, 20.), 20.) as value_source_value
  FROM &_vdw_vitalsigns vs 
    INNER JOIN omop.person pn
    ON vs.mrn = pn.person_source_value
    LEFT JOIN omop.visit_occurrence vo
    ON vs.enc_id = vo.visit_source_value
  WHERE vs.pulse_raw ne ''
    ;
quit;

/*
proc sql;
  create table tmp_meas_vitals_preg as
  select DISTINCT
    pn.person_id
    ,45885207 as measurement_concept_id
    ,vs.measure_date as measurement_date
    ,put(vs.measure_date, date.)||' '||put(vs.measure_time, time.) as measurement_datetime
    ,44818701 as measurement_type_concept_id
    ,4172703 as operator_concept_id
    ,put(vs.kpwa_known_pregnancy, float4.) as value_as_number
    ,0 as value_as_concept_id
    ,8541 as unit_concept_id
    ,0 as range_low
    ,0 as range_high
    ,vo.provider_id
    ,vo.visit_occurrence_id
    ,'LA6530-5' as measurement_source_value
    ,45885207 as measurement_source_concept_id
    ,'' as unit_source_value
    ,put(vs.kpwa_known_pregnancy, 20.) as value_source_value
  FROM &_vdw_vitalsigns vs 
    INNER JOIN omop.person pn
    ON vs.mrn = pn.person_source_value
    LEFT JOIN omop.visit_occurrence vo
    ON vs.enc_id = vo.visit_source_value
  WHERE vs.kpwa_known_pregnancy = 1
  ;
quit;
*/

proc sql;
  create table omop.measurement as
  select 
    monotonic() as measurement_id
    , msr.person_id
    , msr.measurement_concept_id
    , msr.measurement_date
    , input(msr.measurement_datetime, datetime.) as measurement_datetime
    /* , msr.measurement_time v6*/
    , msr.measurement_type_concept_id
    , msr.operator_concept_id
    , msr.value_as_number
    , msr.value_as_concept_id
    , msr.unit_concept_id
    , msr.range_low
    , msr.range_high
    , msr.provider_id
    , msr.visit_occurrence_id
    /* , msr.visit_detail_id v6*/
    , msr.measurement_source_value
    , msr.measurement_source_concept_id
    , msr.unit_source_value
    , msr.value_source_value
  from
  (
  select 
    person_id
    , coalesce (measurement_concept_id, 0) as measurement_concept_id
    , input(measurement_date, date.) as measurement_date
    , measurement_datetime 
    , measurement_type_concept_id
    , operator_concept_id
    , value_as_number
    , value_as_concept_id
    , unit_concept_id
    , range_low
    , range_high
    , provider_id
    , visit_occurrence_id
    , measurement_source_value
    , measurement_source_concept_id
    , unit_source_value
    , value_source_value as value_source_value
  from work.tmp_measurement_labs 
  where measurement_source_value is not null 
  UNION 
  SELECT * FROM work.tmp_meas_vitals_ht_est
  UNION
  SELECT * FROM work.tmp_meas_vitals_ht
  UNION
  SELECT * FROM work.tmp_meas_vitals_wt_est
  UNION
  SELECT * FROM work.tmp_meas_vitals_wt
  UNION
  SELECT * FROM work.tmp_meas_vitals_bmi
  UNION
  SELECT * FROM work.tmp_meas_vitals_bpd
  UNION
  SELECT * FROM work.tmp_meas_vitals_bps
  UNION
  SELECT * FROM work.tmp_meas_vitals_pulse
  ) msr
  ; 
quit;
