# Before we can load headers we need some paths defined.  They
# may be provided by a system environment variable or just
# having already been set in the workspace
if( !exists( "EMISSPROC_DIR" ) ){
    if( Sys.getenv( "EMISSIONSPROC" ) != "" ){
        EMISSPROC_DIR <- Sys.getenv( "EMISSIONSPROC" )
    } else {
        stop("Could not determine location of emissions data system. Please set the R var EMISSPROC_DIR to the appropriate location")
    }
}

# Universal header file - provides logging, file support, etc.
source(paste(EMISSPROC_DIR,"/../_common/headers/GCAM_header.R",sep=""))
source(paste(EMISSPROC_DIR,"/../_common/headers/EMISSIONS_header.R",sep=""))
logstart( "L252.MACC.R" )
adddep(paste(EMISSPROC_DIR,"/../_common/headers/GCAM_header.R",sep=""))
adddep(paste(EMISSPROC_DIR,"/../_common/headers/EMISSIONS_header.R",sep=""))
printlog( "Marginal Abatement Cost Curves" )

# -----------------------------------------------------------------------------
# 1. Read files

sourcedata( "COMMON_ASSUMPTIONS", "A_common_data", extension = ".R" )
sourcedata( "COMMON_ASSUMPTIONS", "level2_data_names", extension = ".R" )
sourcedata( "MODELTIME_ASSUMPTIONS", "A_modeltime_data", extension = ".R" )
sourcedata( "EMISSIONS_ASSUMPTIONS", "A_emissions_data", extension = ".R" )
GCAM_region_names <- readdata( "COMMON_MAPPINGS", "GCAM_region_names" )
A_regions <- readdata( "EMISSIONS_ASSUMPTIONS", "A_regions" )
A_MACC_TechChange <- readdata( "EMISSIONS_ASSUMPTIONS", "A_MACC_TechChange" )
GCAM_sector_tech <- readdata( "EMISSIONS_MAPPINGS", "GCAM_sector_tech" )
HFC_Abate_GV <- readdata( "EMISSIONS_LEVEL0_DATA", "HFC_Abate_GV" )
L152.MAC_pct_R_S_Proc_EPA <- readdata( "EMISSIONS_LEVEL1_DATA", "L152.MAC_pct_R_S_Proc_EPA" )
L201.ghg_res <- readdata( "EMISSIONS_LEVEL2_DATA", "L201.ghg_res", skip = 4 )
L211.AGREmissions <- readdata( "EMISSIONS_LEVEL2_DATA", "L211.AGREmissions", skip = 4 )
L211.AnEmissions <- readdata( "EMISSIONS_LEVEL2_DATA", "L211.AnEmissions", skip = 4 )
L211.AGRBio <- readdata( "EMISSIONS_LEVEL2_DATA", "L211.AGRBio", skip = 4 )
L232.nonco2_prc <- readdata( "EMISSIONS_LEVEL2_DATA", "L232.nonco2_prc", skip = 4 )
L241.hfc_all <- readdata( "EMISSIONS_LEVEL2_DATA", "L241.hfc_all", skip = 4 )
L241.pfc_all <- readdata( "EMISSIONS_LEVEL2_DATA", "L241.pfc_all", skip = 4 )

# -----------------------------------------------------------------------------
# 2. Build tables for CSVs
printlog( "Prepare the table with all MAC curves for matching" )
L252.MAC_pct_R_S_Proc_EPA <- melt( L152.MAC_pct_R_S_Proc_EPA, id.vars = EPA_MACC_names, variable.name = "tax", value.name = "mac.reduction" )
L252.MAC_pct_R_S_Proc_EPA$tax <- as.numeric( sub( "X", "", L252.MAC_pct_R_S_Proc_EPA$tax ) )

printlog( "L252.ResMAC_fos: Fossil resource MAC curves" )
printlog( "NOTE: only applying the fossil resource MAC curves to the CH4 emissions")
L252.ResMAC_fos <- subset( L201.ghg_res[ c( "region", "depresource", "Non.CO2" ) ], Non.CO2 == "CH4" )
L252.ResMAC_fos$mac.control <- GCAM_sector_tech$EPA_MACC_Sector[
      match( paste( "out_resources", L252.ResMAC_fos$depresource ),
             paste( GCAM_sector_tech$sector, GCAM_sector_tech$subsector ) ) ]
L252.ResMAC_fos <- repeat_and_add_vector( L252.ResMAC_fos, "tax", MAC_taxes )
L252.ResMAC_fos <- L252.ResMAC_fos[ order( L252.ResMAC_fos$region, L252.ResMAC_fos$depresource ), ]
L252.ResMAC_fos$mac.reduction <- NA #until we have the EPA region for matching
L252.ResMAC_fos$EPA_region <- A_regions$MAC_region[ match( L252.ResMAC_fos$region, A_regions$region ) ]
L252.ResMAC_fos$mac.reduction <- round(
      L252.MAC_pct_R_S_Proc_EPA$mac.reduction[
         match( vecpaste( L252.ResMAC_fos[ c( "EPA_region", "mac.control", "tax" ) ] ),
                vecpaste( L252.MAC_pct_R_S_Proc_EPA[ c( "EPA_region", "Process", "tax" ) ] ) ) ],
      digits_MACC )
L252.ResMAC_fos <- na.omit( L252.ResMAC_fos )
# Add column for market variable
L252.ResMAC_fos$market.name <- MAC_Market
# Remove EPA_Region - useful up to now for diagnostic, but not needed for csv->xml conversion
L252.ResMAC_fos <- L252.ResMAC_fos[, names( L252.ResMAC_fos ) != "EPA_region" ]

printlog( "L252.AgMAC: Agricultural abatement (including bioenergy)" )
L252.AgMAC <- rbind(
      subset( L211.AGREmissions[ c( names_AgTechYr, "Non.CO2" ) ], year == min( L211.AGREmissions$year ) & Non.CO2 %in% ag_MACC_GHG_names ),
      subset( L211.AGRBio[ c( names_AgTechYr, "Non.CO2" ) ], year == min( L211.AGREmissions$year ) & Non.CO2 %in% ag_MACC_GHG_names ) )
L252.AgMAC$mac.control <- GCAM_sector_tech$EPA_MACC_Sector[
      match( L252.AgMAC$AgSupplySector, GCAM_sector_tech$supplysector ) ]
#dropping jatropha b/c it isn't in the tech table, and wasn't considered in the epa analysis anyway
L252.AgMAC <- na.omit( L252.AgMAC )
L252.AgMAC <- repeat_and_add_vector( L252.AgMAC, "tax", MAC_taxes )
L252.AgMAC <- L252.AgMAC[ order( L252.AgMAC$region, L252.AgMAC$AgProductionTechnology ), ]
L252.AgMAC$mac.reduction <- NA #until we have the EPA region for matching
L252.AgMAC$EPA_region <- A_regions$MAC_region[ match( L252.AgMAC$region, A_regions$region ) ]
L252.AgMAC$mac.reduction <- round(
      L252.MAC_pct_R_S_Proc_EPA$mac.reduction[
         match( vecpaste( L252.AgMAC[ c( "EPA_region", "mac.control", "tax" ) ] ),
                vecpaste( L252.MAC_pct_R_S_Proc_EPA[ c( "EPA_region", "Process", "tax" ) ] ) ) ],
      digits_MACC )
L252.AgMAC <- na.omit( L252.AgMAC )
# Add column for market variable
L252.AgMAC$market.name <- MAC_Market
# Remove EPA_Region - useful up to now for diagnostic, but not needed for csv->xml conversion
L252.AgMAC <- L252.AgMAC[, names( L252.AgMAC ) != "EPA_region" ]

printlog( "L252.MAC_an: Abatement from animal production" )
L252.MAC_an <- subset( L211.AnEmissions[ c( names_StubTechYr, "Non.CO2" ) ], year == min( L211.AnEmissions$year ) & Non.CO2 %in% ag_MACC_GHG_names )
L252.MAC_an$mac.control <- GCAM_sector_tech$EPA_MACC_Sector[
      match( L252.MAC_an$supplysector, GCAM_sector_tech$supplysector ) ]
L252.MAC_an <- repeat_and_add_vector( L252.MAC_an, "tax", MAC_taxes )
L252.MAC_an <- L252.MAC_an[ order( L252.MAC_an$region, L252.MAC_an$supplysector, L252.MAC_an$subsector, L252.MAC_an$stub.technology, L252.MAC_an$Non.CO2 ), ]
L252.MAC_an$mac.reduction <- NA #until we have the EPA region for matching
L252.MAC_an$EPA_region <- A_regions$MAC_region[ match( L252.MAC_an$region, A_regions$region ) ]
L252.MAC_an$mac.reduction <- round(
      L252.MAC_pct_R_S_Proc_EPA$mac.reduction[
         match( vecpaste( L252.MAC_an[ c( "EPA_region", "mac.control", "tax" ) ] ),
                vecpaste( L252.MAC_pct_R_S_Proc_EPA[ c( "EPA_region", "Process", "tax" ) ] ) ) ],
      digits_MACC )
L252.MAC_an <- na.omit( L252.MAC_an )
# Add column for market variable
L252.MAC_an$market.name <- MAC_Market
# Remove EPA_Region - useful up to now for diagnostic, but not needed for csv->xml conversion
L252.MAC_an <- L252.MAC_an[, names( L252.MAC_an ) != "EPA_region" ]

printlog( "L252.MAC_prc: Abatement from industrial and urban processes" )
L252.MAC_prc <- subset( L232.nonco2_prc[ c( names_StubTechYr, "Non.CO2" ) ], year == min( L232.nonco2_prc$year ) & Non.CO2 %in% GHG_names )
L252.MAC_prc$mac.control <- GCAM_sector_tech$EPA_MACC_Sector[
      match( vecpaste( L252.MAC_prc[ c( supp, subs, "stub.technology" ) ] ),
             vecpaste( GCAM_sector_tech[ c( supp, subs, "stub.technology" ) ] ) ) ]
L252.MAC_prc <- repeat_and_add_vector( L252.MAC_prc, "tax", MAC_taxes )
L252.MAC_prc <- L252.MAC_prc[ order( L252.MAC_prc$region, L252.MAC_prc$supplysector, L252.MAC_prc$subsector, L252.MAC_prc$stub.technology, L252.MAC_prc$Non.CO2 ), ]
L252.MAC_prc$mac.reduction <- NA #until we have the EPA region for matching
L252.MAC_prc$EPA_region <- A_regions$MAC_region[ match( L252.MAC_prc$region, A_regions$region ) ]
L252.MAC_prc$mac.reduction <- round(
      L252.MAC_pct_R_S_Proc_EPA$mac.reduction[
         match( vecpaste( L252.MAC_prc[ c( "EPA_region", "mac.control", "tax" ) ] ),
                vecpaste( L252.MAC_pct_R_S_Proc_EPA[ c( "EPA_region", "Process", "tax" ) ] ) ) ],
      digits_MACC )
L252.MAC_prc <- na.omit( L252.MAC_prc )
# Add column for market variable
L252.MAC_prc$market.name <- MAC_Market
# Remove EPA_Region - useful up to now for diagnostic, but not needed for csv->xml conversion
L252.MAC_prc <- L252.MAC_prc[, names( L252.MAC_prc ) != "EPA_region" ]

printlog( "L252.MAC_higwp: Abatement from HFCs, PFCs, and SF6" )
L252.MAC_higwp <- rbind(
      subset( L241.hfc_all[ c( names_StubTechYr, "Non.CO2" ) ], year == min( L241.hfc_all$year ) ),
      subset( L241.pfc_all[ c( names_StubTechYr, "Non.CO2" ) ], year == min( L241.pfc_all$year ) ) )
L252.MAC_higwp$mac.control <- GCAM_sector_tech$EPA_MACC_Sector[
      match( vecpaste( L252.MAC_higwp[ c( supp, subs, "stub.technology" ) ] ),
             vecpaste( GCAM_sector_tech[ c( supp, subs, "stub.technology" ) ] ) ) ]
L252.MAC_higwp <- repeat_and_add_vector( L252.MAC_higwp, "tax", MAC_taxes )
L252.MAC_higwp <- L252.MAC_higwp[ order( L252.MAC_higwp$region, L252.MAC_higwp$supplysector, L252.MAC_higwp$subsector, L252.MAC_higwp$stub.technology, L252.MAC_higwp$Non.CO2 ), ]
L252.MAC_higwp$mac.reduction <- NA #until we have the EPA region for matching
L252.MAC_higwp$EPA_region <- A_regions$MAC_region[ match( L252.MAC_higwp$region, A_regions$region ) ]
L252.MAC_higwp$mac.reduction <- round(
      L252.MAC_pct_R_S_Proc_EPA$mac.reduction[
         match( vecpaste( L252.MAC_higwp[ c( "EPA_region", "mac.control", "tax" ) ] ),
                vecpaste( L252.MAC_pct_R_S_Proc_EPA[ c( "EPA_region", "Process", "tax" ) ] ) ) ],
      digits_MACC )
L252.MAC_higwp <- na.omit( L252.MAC_higwp )
# Add column for market variable
L252.MAC_higwp$market.name <- MAC_Market
# Remove EPA_Region - useful up to now for diagnostic, but not needed for csv->xml conversion
L252.MAC_higwp <- L252.MAC_higwp[, names( L252.MAC_higwp ) != "EPA_region" ]

if ( use_GV_MAC ) {
  printlog( "L252.MAC_higwp_GV: Abatement from HFCs, PFCs, and SF6 using Guus Velders data for HFCs" )
  L252.MAC_pfc <- subset( L252.MAC_higwp, Non.CO2 %in% c( "C2F6", "CF4", "SF6" ))
  
  L252.HFC_Abate_GV <- subset( HFC_Abate_GV, Species == "Total_HFCs" & Year %in% c( 2020, 2025, 2030, 2035, 2050, 2100 ))
  L252.MAC_hfc_gv_0 <- subset( L252.MAC_higwp, Non.CO2 %!in% c( "C2F6", "CF4", "SF6" ) & tax == 0 )
  L252.MAC_hfc_gv_0$mac.reduction <- 0
  
  L252.MAC_hfc_gv_10 <- L252.MAC_hfc_gv_0
  L252.MAC_hfc_gv_10$tax <- 10
  L252.MAC_hfc_gv_10$mac.reduction <- L252.HFC_Abate_GV$PCT_ABATE[ L252.HFC_Abate_GV$Year == 2020 ]
  
  L252.MAC_hfc_gv_25 <- L252.MAC_hfc_gv_0
  L252.MAC_hfc_gv_25$tax <- 25
  L252.MAC_hfc_gv_25$mac.reduction <- L252.HFC_Abate_GV$PCT_ABATE[ L252.HFC_Abate_GV$Year == 2025 ]
  
  L252.MAC_hfc_gv_50 <- L252.MAC_hfc_gv_0
  L252.MAC_hfc_gv_50$tax <- 50
  L252.MAC_hfc_gv_50$mac.reduction <- L252.HFC_Abate_GV$PCT_ABATE[ L252.HFC_Abate_GV$Year == 2035 ]
  
  L252.MAC_hfc_gv_100 <- L252.MAC_hfc_gv_0
  L252.MAC_hfc_gv_100$tax <- 100
  L252.MAC_hfc_gv_100$mac.reduction <- L252.HFC_Abate_GV$PCT_ABATE[ L252.HFC_Abate_GV$Year == 2050 ]
  
  L252.MAC_hfc_gv_200 <- L252.MAC_hfc_gv_0
  L252.MAC_hfc_gv_200$tax <- 200
  L252.MAC_hfc_gv_200$mac.reduction <- L252.HFC_Abate_GV$PCT_ABATE[ L252.HFC_Abate_GV$Year == 2100 ]
  
  L252.MAC_higwp <- rbind( L252.MAC_pfc, L252.MAC_hfc_gv_0, L252.MAC_hfc_gv_10, L252.MAC_hfc_gv_25,
                           L252.MAC_hfc_gv_50, L252.MAC_hfc_gv_100, L252.MAC_hfc_gv_200)
}

printlog( "L252.MAC_TC_SSP1: Tech Change on MACCs for SSP1" )
L252.MAC_Ag_TC_SSP1 <- L252.AgMAC[ names( L252.AgMAC ) != "EPA_region" ]
L252.MAC_Ag_TC_SSP1$tech.change <- A_MACC_TechChange$tech_change[ match( paste( "SSP1", L252.MAC_Ag_TC_SSP1$mac.control ),
                                                                         paste( A_MACC_TechChange$scenario, A_MACC_TechChange$MAC ))]
L252.MAC_Ag_TC_SSP1 <- na.omit( L252.MAC_Ag_TC_SSP1 )

L252.MAC_An_TC_SSP1 <- L252.MAC_an[ names( L252.MAC_an ) != "EPA_region" ]
L252.MAC_An_TC_SSP1$tech.change <- A_MACC_TechChange$tech_change[ match( paste( "SSP1", L252.MAC_An_TC_SSP1$mac.control ),
                                                                         paste( A_MACC_TechChange$scenario, A_MACC_TechChange$MAC ))]
L252.MAC_An_TC_SSP1 <- na.omit( L252.MAC_An_TC_SSP1 )

L252.MAC_prc_TC_SSP1 <- L252.MAC_prc[ names( L252.MAC_prc ) != "EPA_region" ]
L252.MAC_prc_TC_SSP1$tech.change <- A_MACC_TechChange$tech_change[ match( paste( "SSP1", L252.MAC_prc_TC_SSP1$mac.control ),
                                                                         paste( A_MACC_TechChange$scenario, A_MACC_TechChange$MAC ))]
L252.MAC_prc_TC_SSP1 <- na.omit( L252.MAC_prc_TC_SSP1 )

L252.MAC_res_TC_SSP1 <- L252.ResMAC_fos[ names( L252.ResMAC_fos ) != "EPA_region" ]
L252.MAC_res_TC_SSP1$tech.change <- A_MACC_TechChange$tech_change[ match( paste( "SSP1", L252.MAC_res_TC_SSP1$mac.control ),
                                                                         paste( A_MACC_TechChange$scenario, A_MACC_TechChange$MAC ))]
L252.MAC_res_TC_SSP1 <- na.omit( L252.MAC_res_TC_SSP1 )

printlog( "L252.MAC_TC_SSP2: Tech Change on MACCs for SSP2" )
L252.MAC_Ag_TC_SSP2 <- L252.AgMAC[ names( L252.AgMAC ) != "EPA_region" ]
L252.MAC_Ag_TC_SSP2$tech.change <- A_MACC_TechChange$tech_change[ match( paste( "SSP2", L252.MAC_Ag_TC_SSP2$mac.control ),
                                                                         paste( A_MACC_TechChange$scenario, A_MACC_TechChange$MAC ))]
L252.MAC_Ag_TC_SSP2 <- na.omit( L252.MAC_Ag_TC_SSP2 )

L252.MAC_An_TC_SSP2 <- L252.MAC_an[ names( L252.MAC_an ) != "EPA_region" ]
L252.MAC_An_TC_SSP2$tech.change <- A_MACC_TechChange$tech_change[ match( paste( "SSP2", L252.MAC_An_TC_SSP2$mac.control ),
                                                                         paste( A_MACC_TechChange$scenario, A_MACC_TechChange$MAC ))]
L252.MAC_An_TC_SSP2 <- na.omit( L252.MAC_An_TC_SSP2 )

L252.MAC_prc_TC_SSP2 <- L252.MAC_prc[ names( L252.MAC_prc ) != "EPA_region" ]
L252.MAC_prc_TC_SSP2$tech.change <- A_MACC_TechChange$tech_change[ match( paste( "SSP2", L252.MAC_prc_TC_SSP2$mac.control ),
                                                                          paste( A_MACC_TechChange$scenario, A_MACC_TechChange$MAC ))]
L252.MAC_prc_TC_SSP2 <- na.omit( L252.MAC_prc_TC_SSP2 )

L252.MAC_res_TC_SSP2 <- L252.ResMAC_fos[ names( L252.ResMAC_fos ) != "EPA_region" ]
L252.MAC_res_TC_SSP2$tech.change <- A_MACC_TechChange$tech_change[ match( paste( "SSP2", L252.MAC_res_TC_SSP2$mac.control ),
                                                                          paste( A_MACC_TechChange$scenario, A_MACC_TechChange$MAC ))]
L252.MAC_res_TC_SSP2 <- na.omit( L252.MAC_res_TC_SSP2 )

printlog( "L252.MAC_TC_SSP5: Tech Change on MACCs for SSP5" )
L252.MAC_Ag_TC_SSP5 <- L252.AgMAC[ names( L252.AgMAC ) != "EPA_region" ]
L252.MAC_Ag_TC_SSP5$tech.change <- A_MACC_TechChange$tech_change[ match( paste( "SSP5", L252.MAC_Ag_TC_SSP5$mac.control ),
                                                                         paste( A_MACC_TechChange$scenario, A_MACC_TechChange$MAC ))]
L252.MAC_Ag_TC_SSP5 <- na.omit( L252.MAC_Ag_TC_SSP5 )

L252.MAC_An_TC_SSP5 <- L252.MAC_an[ names( L252.MAC_an ) != "EPA_region" ]
L252.MAC_An_TC_SSP5$tech.change <- A_MACC_TechChange$tech_change[ match( paste( "SSP5", L252.MAC_An_TC_SSP5$mac.control ),
                                                                         paste( A_MACC_TechChange$scenario, A_MACC_TechChange$MAC ))]
L252.MAC_An_TC_SSP5 <- na.omit( L252.MAC_An_TC_SSP5 )

L252.MAC_prc_TC_SSP5 <- L252.MAC_prc[ names( L252.MAC_prc ) != "EPA_region" ]
L252.MAC_prc_TC_SSP5$tech.change <- A_MACC_TechChange$tech_change[ match( paste( "SSP5", L252.MAC_prc_TC_SSP5$mac.control ),
                                                                          paste( A_MACC_TechChange$scenario, A_MACC_TechChange$MAC ))]
L252.MAC_prc_TC_SSP5 <- na.omit( L252.MAC_prc_TC_SSP5 )

L252.MAC_res_TC_SSP5 <- L252.ResMAC_fos[ names( L252.ResMAC_fos ) != "EPA_region" ]
L252.MAC_res_TC_SSP5$tech.change <- A_MACC_TechChange$tech_change[ match( paste( "SSP5", L252.MAC_res_TC_SSP5$mac.control ),
                                                                          paste( A_MACC_TechChange$scenario, A_MACC_TechChange$MAC ))]
L252.MAC_res_TC_SSP5 <- na.omit( L252.MAC_res_TC_SSP5 )

# -----------------------------------------------------------------------------
# 3. Write all csvs as tables, and paste csv filenames into a single batch XML file
write_mi_data( L252.ResMAC_fos, "ResMAC", "EMISSIONS_LEVEL2_DATA", "L252.ResMAC_fos", "EMISSIONS_XML_BATCH", "batch_all_energy_emissions.xml" ) 
write_mi_data( L252.AgMAC, "AgMAC", "EMISSIONS_LEVEL2_DATA", "L252.AgMAC", "EMISSIONS_XML_BATCH", "batch_all_aglu_emissions.xml" ) 
write_mi_data( L252.MAC_an, "MAC", "EMISSIONS_LEVEL2_DATA", "L252.MAC_an", "EMISSIONS_XML_BATCH", "batch_all_aglu_emissions.xml" ) 
write_mi_data( L252.MAC_prc, "MAC", "EMISSIONS_LEVEL2_DATA", "L252.MAC_prc", "EMISSIONS_XML_BATCH", "batch_ind_urb_processing_sectors.xml" ) 
write_mi_data( L252.MAC_higwp, "MAC", "EMISSIONS_LEVEL2_DATA", "L252.MAC_higwp", "EMISSIONS_XML_BATCH", "batch_all_fgas_emissions.xml" ) 

#This is the last file that refers to agricultural emissions
insert_file_into_batchxml( "EMISSIONS_XML_BATCH", "batch_all_aglu_emissions.xml", "EMISSIONS_XML_FINAL", "all_aglu_emissions.xml", "", xml_tag="outFile" )

write_mi_data( L252.MAC_Ag_TC_SSP1, "AgMACTC", "EMISSIONS_LEVEL2_DATA", "L252.MAC_Ag_TC_SSP1", "EMISSIONS_XML_BATCH", "batch_MACC_TC_SSP1.xml" ) 
write_mi_data( L252.MAC_An_TC_SSP1, "MACTC", "EMISSIONS_LEVEL2_DATA", "L252.MAC_An_TC_SSP1", "EMISSIONS_XML_BATCH", "batch_MACC_TC_SSP1.xml" ) 
write_mi_data( L252.MAC_prc_TC_SSP1, "MACTC", "EMISSIONS_LEVEL2_DATA", "L252.MAC_prc_TC_SSP1", "EMISSIONS_XML_BATCH", "batch_MACC_TC_SSP1.xml" ) 
write_mi_data( L252.MAC_res_TC_SSP1, "ResMAC", "EMISSIONS_LEVEL2_DATA", "L252.MAC_res_TC_SSP1", "EMISSIONS_XML_BATCH", "batch_MACC_TC_SSP1.xml" ) 
insert_file_into_batchxml( "EMISSIONS_XML_BATCH", "batch_MACC_TC_SSP1.xml", "EMISSIONS_XML_FINAL", "MACC_TC_SSP1.xml", "", xml_tag="outFile" )

write_mi_data( L252.MAC_Ag_TC_SSP2, "AgMACTC", "EMISSIONS_LEVEL2_DATA", "L252.MAC_Ag_TC_SSP2", "EMISSIONS_XML_BATCH", "batch_MACC_TC_SSP2.xml" ) 
write_mi_data( L252.MAC_An_TC_SSP2, "MACTC", "EMISSIONS_LEVEL2_DATA", "L252.MAC_An_TC_SSP2", "EMISSIONS_XML_BATCH", "batch_MACC_TC_SSP2.xml" ) 
write_mi_data( L252.MAC_prc_TC_SSP2, "MACTC", "EMISSIONS_LEVEL2_DATA", "L252.MAC_prc_TC_SSP2", "EMISSIONS_XML_BATCH", "batch_MACC_TC_SSP2.xml" ) 
write_mi_data( L252.MAC_res_TC_SSP2, "ResMAC", "EMISSIONS_LEVEL2_DATA", "L252.MAC_res_TC_SSP2", "EMISSIONS_XML_BATCH", "batch_MACC_TC_SSP2.xml" ) 
insert_file_into_batchxml( "EMISSIONS_XML_BATCH", "batch_MACC_TC_SSP2.xml", "EMISSIONS_XML_FINAL", "MACC_TC_SSP2.xml", "", xml_tag="outFile" )

write_mi_data( L252.MAC_Ag_TC_SSP5, "AgMACTC", "EMISSIONS_LEVEL2_DATA", "L252.MAC_Ag_TC_SSP5", "EMISSIONS_XML_BATCH", "batch_MACC_TC_SSP5.xml" ) 
write_mi_data( L252.MAC_An_TC_SSP5, "MACTC", "EMISSIONS_LEVEL2_DATA", "L252.MAC_An_TC_SSP5", "EMISSIONS_XML_BATCH", "batch_MACC_TC_SSP5.xml" ) 
write_mi_data( L252.MAC_prc_TC_SSP5, "MACTC", "EMISSIONS_LEVEL2_DATA", "L252.MAC_prc_TC_SSP5", "EMISSIONS_XML_BATCH", "batch_MACC_TC_SSP5.xml" ) 
write_mi_data( L252.MAC_res_TC_SSP5, "ResMAC", "EMISSIONS_LEVEL2_DATA", "L252.MAC_res_TC_SSP5", "EMISSIONS_XML_BATCH", "batch_MACC_TC_SSP5.xml" ) 
insert_file_into_batchxml( "EMISSIONS_XML_BATCH", "batch_MACC_TC_SSP5.xml", "EMISSIONS_XML_FINAL", "MACC_TC_SSP5.xml", "", xml_tag="outFile" )

logstop()
