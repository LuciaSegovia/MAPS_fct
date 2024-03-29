###############################################################################
#                                                                             #        
#                   IMPORTING AND TIDYING                                     #  
#              KENYA FOOD COMPOSITION TABLE, 2018                             # 
#                                                                             #   
#                                                                             #   
###############################################################################


##0) DOWNLOADING KENYA FCT FROM HUMAN NUTRION AND DIETETICS UNIT, MOH, KENYA

#Only need to do it once!

f <- "http://www.nutritionhealth.or.ke/wp-content/uploads/Downloads/Kenya%20Food%20Composition%20Tables%20Excel%20files%202018.xlsx"

download.file(f,"./data/MOH-KENFCT_2018.xlsx",
              method="wininet", #use "curl" for OS X / Linux, "wininet" for Windows
              mode="wb")


##1) LOADING PACKAGES AND KENYA FCT 

library(tidyverse)

#Check all the sheet in the spreadsheet
readxl::excel_sheets(here::here('data', "MOH-KENFCT_2018.xlsx"))

readxl::read_excel(here::here('data', "MOH-KENFCT_2018.xlsx"), sheet = 4, skip = 2) %>%
  tail()


#Customized saving FCT

kenfct <- readxl::read_excel(here::here('data', "MOH-KENFCT_2018.xlsx"),
                             sheet = 4, skip = 2) %>%
  mutate(FCT = 'KENFCT') %>% #adding a column with the FCT short-name
  slice(1:1240) %>%   #removing last rows that are empty only provide notes info
  glimpse()

##2) TIDYING KENYA FCT 

#Rename variables acc. to tagnames (FAO/INFOODS)
#We are not renaming Fatty acids nor AAs

ken_names <- c('code', 'fooditem', 'EDIBLE', 'ENERC2', 'ENERC1', 'WATER', 
              'PROTCNT', 'FAT',  'CHOAVLDF', 'FIBTG', 'ASH', 
              'CA', 'FE', 'MG', 'P', 'K', 'NA.', 'ZN', 'SE',
              'VITA_RAE', 'VITA', 'RETOL', 'CARTBEQ', 
              'THIA', 'RIBF', 'NIA', 'FOLDFE', 'FOLFD',
              'VITB12', 'VITC', 'CHOLE', 'OXALAC', 'PHYTCPPD', 'IP3', 'IP4',
              'IP5', 'IP6','FASAT', "FAMS","FAPU", 'FCT')

kenfct <- kenfct %>% rename_at(vars(1:37, 60:62, 320),  ~ken_names) 

#creating variable 'foodgroups'

kenfg <- kenfct %>%  filter(code %in% c(1:15)) %>% pull(fooditem)

kenfct <- kenfct %>% mutate(foodgroup = case_when(
  str_detect(code, "[:digit:]{5}") & str_starts(code, '10') ~ kenfg[10],
  str_starts(code, '10') ~ kenfg[1],
  str_starts(code, '20') ~ kenfg[2],
  str_starts(code, '30') ~ kenfg[3],
  str_starts(code, '40') ~ kenfg[4],
  str_starts(code, '50') ~ kenfg[5],
  str_starts(code, '60') ~ kenfg[6],
  str_starts(code, '70') ~ kenfg[7],
  str_starts(code, '80') ~ kenfg[8],
  str_starts(code, '90') ~ kenfg[9],
  str_starts(code, '11') ~ kenfg[11],
  str_starts(code, '12') ~ kenfg[12],
  str_starts(code, '13') ~ kenfg[13],
  str_starts(code, '14') ~ kenfg[14],
  str_starts(code, '15') ~ kenfg[15])) %>% 
  filter(!is.na(ENERC1), !is.na(fooditem)) #Removing NA, SD/min-max


#Creating a dataset w/ the values that were of low quality [],  
#trace, fortified w/ folic acid or normal

ken_meta_quality <- kenfct %>% 
  mutate_at(vars(EDIBLE:`Fatty acid 24:6 (/100 g FA)`),  ~case_when(
  str_detect(. , '\\[.*?\\]') ~ "low_quality", 
  str_detect(. , '[*]') ~ "folic-fortified", 
  str_detect(. , 'tr') ~ "trace",
  TRUE ~ "normal_value"))

#codes of the items identified as fortified with folic acid
folac <- kenfct %>% filter(str_detect(FOLDFE, '[*]')) %>% pull(code) 

#Extracting variables calculated with different (lower quality) method 
#and reported as using [] and removing * from FOLDFE
#and changing tr w/ 0

no_brackets_tr_ast <- function(i){
  case_when(
    str_detect(i, 'tr|[tr]') ~ "0",
    str_detect(i, '\\[.*?\\]')  ~ str_extract(i, '(?<=\\[).*?(?=\\])'),
    str_detect(i, '[*]')  ~ str_extract(i, "[:digit:]+"),
    TRUE ~ i)
}

kenfct <- kenfct %>% 
  mutate_at(vars(EDIBLE:`Fatty acid 24:6 (/100 g FA)`), no_brackets_tr_ast)

#Check that all tr, [] and * are removed 
#NOTE: tr will be found in non-numeric variables (i.e., fooditem)
kenfct %>% str_which(.,"tr|[tr]|[*]|\\[.*?\\]")


#Adding the reference (biblioID) and Scientific name to kenfct

kenfct <- kenfct %>% left_join(., readxl::read_excel(here::here('data', "MOH-KENFCT_2018.xlsx"), 
                   sheet = 7, skip = 2) %>%
                  janitor::clean_names() %>% 
                  select(2, 4,5) %>% 
                  mutate_at("code_kfct18", as.character),
                  by = c("code" = "code_kfct18")) 

  
#Reordering variables and converting nutrient variables into numeric

kenfct <- kenfct %>% dplyr::relocate(c(scientific_name, foodgroup, biblio_id),
                                     .after = fooditem) %>%
  dplyr::relocate(FCT, .before = code) %>% 
  mutate_at(vars(EDIBLE:`Fatty acid 24:6 (/100 g FA)`), as.numeric)

kenfct %>% head()

#Calculating FOLAC and checking folate fortification

kenfct %>%  
  mutate(FOLAC = (FOLDFE-FOLFD)/1.7) %>% select(code, FOLAC) %>% 
  filter(!code %in% folac, FOLAC> 0) %>% arrange(FOLAC) %>% knitr::kable()

#Detecting FOLAC (folic acid used in fortified food)
#15065 - Fortified. Misreported in excel but reported in pdf
#15019 - It seems fortified, although it's not reported as such. 

## Fixing name descriptions and scientific names -------

#The scientific name of Coriander, leaves, fresh, raw
kenfct$scientific_name[kenfct$code == "13011"] <- "Coriandrum sativum"

#The scientific name of coconut (3 entries) 
kenfct$scientific_name[kenfct$code %in% c("10002", "10003", "10004")] <- "Cocos nucifera"

#There is a typo in "Roti"
kenfct$fooditem[kenfct$code == "15003"] <- "Roti (Indian Chapati)"

 
## 3) MAPS compatible fct format -----

# Loading data

source("dictionary.R")

#getting the names of all the standard variables names, to filter them afterward
var.name <- read.csv(here::here("metadata", "fct-variable-names.csv")) %>% 
  select(Column.Name) %>% pull()


## Adding dictionary (genus) code -------


ken_genus <- tribble(
  ~ref_fctcode,   ~ID_3, ~confidence,
  "1004",   "F0022.03",    "m",
  "6001",   "22241.01.01", "h",
  "12004",  "F0665.01",    "m", 
  "12003",  "23912.02.01", "m", 
  "4016",   "1232.01"  ,   "m",
  "11001",  "2910.01"  ,   "h",
  "10010",  "1379.9.01" ,  "l", 
  # "13027",  "1699.02"   ,  "m", #salt, ionized 
  "15026",  "F0022.05"  ,  "h",
  "1031",   "23710.01"  ,  "m", 
  "13028",  "1699.03"   ,  "h",
  "11003",  "23520.01"  ,  "m",
  "12005",  "23914.02"  ,  "m",
  "13031",  "21399.01.01" ,"m",
  "12008",  "24212.02.01" ,"m",
  "6026",   "22230.01.01" ,"m",
  "10006", "1442.01", "h",
  "05009", "1491.02.01", "l",
  "1041", "1199.9.01", "m",
  "1045", "111.01", "m", 
  "3001", "1701.05", "m", 
  "3010", "1703.01", "m",
  "13023", "1253.02.01", "l", 
  "2009", "1510.01", "m", 
  "10009", "142.01", "l",
  "13006", "1652.01", "m", 
  "13007", "1652.02", "m", 
  "7009", "21121.01.01", "h", 
  "8010", "1501.05", "m",
  "1007", "F0020.01", "m",
  "6008", "22241.02.01", "h", 
  "1034" ,  "23161.01.01", "m",
  "13017", "1699.07", "h", 
  "3019", "1709.9.01", "m", 
  "10014", "1444.01", "m", 
  "10015", "1445.01", "m",
  "4019", "1212.04", "m",
  "4022", "1214.01", "h",
  "13019", "1252.01", "m", 
  "5024", "1317.01", "m", 
  "4011", "1251.01", "m", 
  "2005", "1290.9.01", "m",
  "8002", "1505.07", "h",
  "4034", "1290.9.02", "m", 
  "2004", "1313.01", "m", 
  "4001", "1215.02", "m", 
  "1023", "1290.01.01", "h", 
  "1051", "1290.01.03", "m", 
  "13024", "1253.01.01", "h",
  "6007", "22120.02", "h",
  "13011", "1290.9.03", "h", 
  "7020", "21113.02.01", "h", #assumed w/o bones bc EP = 1
  "15125", "F0022.08", "h", 
  "13015", "1699.10", "h", 
  "4013", "1290.9.04", "h", 
  "1005", "F0020.02", "m", 
  "5012", "1319.01", "m", 
  "7019", "21115.01", "m",
  "10003", "1460.02", "m",
  "9011", "34550.02", "m", 
  "9001", "F1243.02", "m",
  "5028", "1342.01.01", "m",
  "4014", "1235.04", "m", 
  "4037", "21399.02.01", "m", 
  "1030", "23710.02", "h",
  "15081", "23914.03", "m",
  "6019", "22110.02.01", "h",
  "5025", "1319.02", "h",
  "8011", "1553.02", "h",
  "5031", "21346.01", "h",
  "4021", "1254.01", "h", 
  "4012", "1213.01", "m", 
  "5027", "1345.01", "m",
  "5034", "1354.01", "h", 
  "7025", "21184.02.01", "m",#No info on prep.
  "7022", "21184.01.01", "m", #No info on prep.
  "4004", "1213.02", "h", 
  "1018", "21691.02.01", "h",
  "8012", "1527.02", "h",
  "4008", "1231.01", "h",
  "4009", "1231.02", "h",
  "4010", "1231.03", "h", 
  "15019", "F0020.06", "h", 
  "15020", "F0020.04", "h", 
  "15130" ,"F0020.05", "h",
  "15003", "F0022.04", "m", 
  "15025", "F0022.07", "m",
  "7001" , "21111.01.03", "h",
  "7002" , "21111.01.01", "h"
  
)


ken_genus <- read.csv(here::here("inter-output", "kenfct_matches.csv")) %>% 
  filter(!FCT.code %in% c("7009", "10010")) %>% #removing chicken - wrong code (21121.02) and macadamia wrong confidence
  select(FCT.code, MAPS.ID.code, Confidence) %>% 
  mutate(confidence = case_when(
    Confidence == "high" ~ "h", 
    Confidence == "medium" ~ "m", 
    Confidence == "low" ~ "l", 
    TRUE ~ Confidence)) %>% select(-Confidence) %>%
  mutate_at("FCT.code", as.character) %>% 
  rename(ref_fctcode = "FCT.code", 
         ID_3 = "MAPS.ID.code") %>% 
  bind_rows(ken_genus) %>% distinct()

dupli <- ken_genus %>%  count(ref_fctcode) %>% 
  filter(n>1) %>% pull(ref_fctcode)

ken_genus %>% filter(ref_fctcode %in% dupli) %>% arrange(desc(ref_fctcode))
kenfct %>% filter(code %in% dupli) %>% arrange(desc(code)) %>% select(code, fooditem)

#Fixing horse bean to broad bean code (but they are all fava vicia)
ken_genus$ID_3[ken_genus$ref_fctcode == "3001"] <-  "1702.02"
#Fixing rice - acc. to SUA for Kenya all milled rice was coded
#23161.02 (whether imported or produced), hence we are changing
ken_genus$ID_3[ken_genus$ref_fctcode == "1034"] <-  "23161.02.01"
#Fixing beef to acc. for fat content variability
ken_genus$ID_3[ken_genus$ref_fctcode == "7004"] <-  "21111.01.02"

#Merging the dictionary codes in the kenfct

kenfct <- kenfct %>% 
  left_join(., ken_genus, by = c("code" = "ref_fctcode")) %>% 
  relocate(ID_3, .after = fooditem)


dim(kenfct)


#Rename variables according to MAPS-standards

MAPS_ken <- kenfct %>% 
  left_join(., ken_genus, by = c("code" = "ref_fctcode")) %>%   
rename(
  original_food_id = "code",
  original_food_name = "fooditem",
  food_genus_id = "ID_3",
  food_genus_description = "FoodName_3",
  food_group = "FoodName_0",
  food_subgroup = "FoodName_1", 
  food_genus_confidence = "confidence",
  fct_name = "FCT",
  data_reference_original_id = "biblio_id",
  moisture_in_g = "WATER",
  energy_in_kcal = "ENERC1",
  energy_in_kj = "ENERC2",
  totalprotein_in_g = "PROTCNT",
  totalfats_in_g = "FAT",
  saturatedfa_in_g = "FASAT", 
  monounsaturatedfa_in_g = "FAMS", 
  polyunsaturatedfa_in_g = "FAPU", 
  cholesterol_in_mg = "CHOLE",
  carbohydrates_in_g = "CHOAVLDF", 
  fibre_in_g = "FIBTG", 
  ash_in_g = "ASH",
  ca_in_mg = "CA", 
  fe_in_mg = "FE",
  mg_in_mg = "MG",
  p_in_mg = "P",
  k_in_mg = "K",
  na_in_mg = "NA.", 
  zn_in_mg = "ZN",
  se_in_mcg = "SE",
  vitamina_in_rae_in_mcg = "VITA_RAE", 
  thiamin_in_mg = "THIA",
  riboflavin_in_mg = "RIBF", 
  niacin_in_mg = "NIA", 
  folate_in_mcg = "FOLFD",
  vitaminb12_in_mcg = "VITB12",
  vitaminc_in_mg = "VITC",
  phyticacid_in_mg = "PHYTCPPD") %>% 
  mutate(
  nitrogen_in_g = "NA", 
  cu_in_mg = "NA",
  mn_in_mcg = "NA",
  i_in_mcg = "NA",
  vitaminb6_in_mg = "NA",
  pantothenate_in_mg = "NA",
  biotin_in_mcg = "NA",
  vitamind_in_mcg = "NA",
  vitamine_in_mg = "NA",
  folicacid_in_mcg = "NA") %>% select(var.name)


MAPS_ken %>% head()

MAPS_ken %>%
readr::write_excel_csv(., 
                       here::here('output', 'MAPS_KENFCT_v1.3.csv')) #that f(x) is to 
                                              #deal w/ special characters 