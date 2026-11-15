-- One row per published individual service. Do not sum these costs to obtain
-- a USPS class total: group costs are independently estimated.
CREATE OR ALTER VIEW gold.usps_service_2025_report_detail AS
SELECT fiscal_year, service_group, service_label,
       CONCAT(service_group, ' | ', service_label) AS service_display,
       revenue_usd, attributable_cost_usd, volume_variable_cost_usd,
       contribution_before_common_costs_usd, source_version, source_locator,
       source_precision, source_url
FROM gold.usps_market_dominant_service_detail_2024_2025
WHERE fiscal_year = 2025;
GO
