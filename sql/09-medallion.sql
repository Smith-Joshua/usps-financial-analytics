-- Called in one serializable transaction by 09-run-medallion.ps1.
IF OBJECT_ID(N'bronze.usps_source_rows', N'U') IS NULL
 CREATE TABLE bronze.usps_source_rows (
  dataset nvarchar(20) NOT NULL, fiscal_year smallint NOT NULL,
  service_group nvarchar(200) NOT NULL, service_label nvarchar(200) NOT NULL,
  source_payload nvarchar(max) NOT NULL,
  CONSTRAINT PK_usps_source_rows PRIMARY KEY(dataset,fiscal_year,service_group,service_label),
  CONSTRAINT CK_usps_source_payload CHECK (ISJSON(source_payload)=1)
 );
SELECT CAST(JSON_VALUE(value,'$.dataset') AS nvarchar(20)) dataset,
 CAST(JSON_VALUE(value,'$.fiscal_year') AS smallint) fiscal_year,
 CAST(JSON_VALUE(value,'$.service_group') AS nvarchar(200)) service_group,
 CAST(JSON_VALUE(value,'$.service_label') AS nvarchar(200)) service_label,
 CAST(value AS nvarchar(max)) source_payload
INTO #incoming_bronze FROM OPENJSON(@payload);
IF (SELECT COUNT(*) FROM #incoming_bronze) <> 88
 OR (SELECT COUNT(*) FROM #incoming_bronze WHERE dataset='market') <> 64
 OR (SELECT COUNT(*) FROM #incoming_bronze WHERE dataset='history') <> 24
 OR EXISTS (SELECT dataset,fiscal_year,service_group,service_label FROM #incoming_bronze GROUP BY dataset,fiscal_year,service_group,service_label HAVING COUNT(*)<>1)
 THROW 50100, 'Unexpected bronze input. No changes applied.', 1;
IF EXISTS (SELECT 1 FROM bronze.usps_source_rows)
BEGIN
 IF EXISTS (SELECT dataset,fiscal_year,service_group,service_label,source_payload COLLATE Latin1_General_100_BIN2 FROM #incoming_bronze
            EXCEPT SELECT dataset,fiscal_year,service_group,service_label,source_payload COLLATE Latin1_General_100_BIN2 FROM bronze.usps_source_rows)
 OR EXISTS (SELECT dataset,fiscal_year,service_group,service_label,source_payload COLLATE Latin1_General_100_BIN2 FROM bronze.usps_source_rows
            EXCEPT SELECT dataset,fiscal_year,service_group,service_label,source_payload COLLATE Latin1_General_100_BIN2 FROM #incoming_bronze)
  THROW 50101, 'Stored bronze differs from the source extract. No changes applied.', 1;
END
ELSE INSERT bronze.usps_source_rows SELECT * FROM #incoming_bronze;

-- These views do all dollar conversion from stored bronze, not input JSON.
EXEC(N'CREATE OR ALTER VIEW silver.usps_market_from_bronze AS
 SELECT b.fiscal_year, TRY_CONVERT(int,JSON_VALUE(b.source_payload,''$.metadata.source_row'')) source_row,
 JSON_VALUE(b.source_payload,''$.metadata.source_version'') source_version, b.service_group, b.service_label,
 JSON_VALUE(b.source_payload,''$.metadata.row_type'') row_type,
 n.revenue_usd, n.attributable_cost_usd, n.volume_variable_cost_usd,
 n.revenue_usd - n.attributable_cost_usd contribution_before_common_costs_usd,
 JSON_VALUE(b.source_payload,''$.metadata.source_locator'') source_locator,
 JSON_VALUE(b.source_payload,''$.metadata.source_precision'') source_precision,
 JSON_VALUE(b.source_payload,''$.metadata.source_url'') source_url
 FROM bronze.usps_source_rows b
 CROSS APPLY (SELECT
 CAST(CAST(JSON_VALUE(b.source_payload,''$.parsed_revenue_millions'') AS decimal(28,14))*1000000 AS decimal(19,2)) revenue_usd,
 CAST(CAST(JSON_VALUE(b.source_payload,''$.parsed_attributable_cost_millions'') AS decimal(28,14))*1000000 AS decimal(19,2)) attributable_cost_usd,
 CAST(CAST(JSON_VALUE(b.source_payload,''$.parsed_volume_cost_millions'') AS decimal(28,14))*1000000 AS decimal(19,2)) volume_variable_cost_usd) n
 WHERE b.dataset=''market''');
EXEC(N'CREATE OR ALTER VIEW silver.usps_history_from_bronze AS
 SELECT b.fiscal_year, JSON_VALUE(b.source_payload,''$.metadata.service_id'') service_id,
 b.service_group,b.service_label,
 CAST(CAST(JSON_VALUE(b.source_payload,''$.parsed_revenue_millions'') AS decimal(28,14))*1000000 AS decimal(19,2)) revenue_usd,
 CAST(CAST(JSON_VALUE(b.source_payload,''$.parsed_attributable_cost_millions'') AS decimal(28,14))*1000000 AS decimal(19,2)) attributable_cost_usd,
 JSON_VALUE(b.source_payload,''$.metadata.source_url'') source_url,
 JSON_VALUE(b.source_payload,''$.metadata.source_locator'') source_locator,
 JSON_VALUE(b.source_payload,''$.metadata.source_version'') source_version,
 JSON_VALUE(b.source_payload,''$.metadata.source_precision'') source_precision,
 JSON_VALUE(b.source_payload,''$.metadata.source_sha256'') source_sha256,
 JSON_VALUE(b.source_payload,''$.metadata.source_extracted_line'') source_extracted_line,
 JSON_VALUE(b.source_payload,''$.metadata.comparability'') comparability
 FROM bronze.usps_source_rows b WHERE b.dataset=''history''');

-- Materialize into empty same-shape tables; validate exact data, including NULLs.
SELECT TOP(0) * INTO #empty_market FROM silver.usps_market_dominant_2024_2025;
INSERT #empty_market SELECT * FROM silver.usps_market_from_bronze;
SELECT TOP(0) * INTO #empty_history FROM silver.usps_historical_selected_candidates;
INSERT #empty_history SELECT * FROM silver.usps_history_from_bronze;
IF (SELECT COUNT(*) FROM #empty_market)<>64 OR (SELECT COUNT(*) FROM #empty_history)<>24
 THROW 50102, 'Bronze to silver row counts differ. No changes applied.', 1;
IF EXISTS (SELECT 1 FROM silver.usps_market_dominant_2024_2025)
BEGIN
 IF EXISTS (SELECT * FROM #empty_market EXCEPT SELECT * FROM silver.usps_market_dominant_2024_2025)
 OR EXISTS (SELECT * FROM silver.usps_market_dominant_2024_2025 EXCEPT SELECT * FROM #empty_market)
  THROW 50103, 'Existing market silver differs from bronze transformation. No changes applied.', 1;
END
ELSE INSERT silver.usps_market_dominant_2024_2025 SELECT * FROM #empty_market;
IF EXISTS (SELECT 1 FROM silver.usps_historical_selected_candidates)
BEGIN
 IF EXISTS (SELECT * FROM #empty_history EXCEPT SELECT * FROM silver.usps_historical_selected_candidates)
 OR EXISTS (SELECT * FROM silver.usps_historical_selected_candidates EXCEPT SELECT * FROM #empty_history)
  THROW 50104, 'Existing history silver differs from bronze transformation. No changes applied.', 1;
END
ELSE INSERT silver.usps_historical_selected_candidates SELECT * FROM #empty_history;
