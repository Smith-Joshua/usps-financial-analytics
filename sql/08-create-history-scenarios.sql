-- Historical source records preserved without overwriting source tables. Group
-- and label matches are candidates, not proof of identical product definitions.
-- Source extracts used in the checked November 10 build:
-- history/historical_service_rows.json SHA256 c39364555043948167fe37e391f928b729f0a2c9483f0344a71f930f657d4a36
-- extract/service_rows.json SHA256 b00a3240f6622d7f6022ef58a5a10820413fbfc027d3fa67ee9fe20dc974477a
CREATE OR ALTER VIEW gold.usps_four_service_history_2018_2025 AS
WITH ServiceMap AS (
 SELECT * FROM (VALUES
  ('single_piece_letters', 'First-Class Mail', 'Single-Piece Letters'),
  ('single_piece_postcards', 'First-Class Mail', 'Single-Piece Postcards'),
  ('presort_letters', 'First-Class Mail', 'Presort Letters'),
  ('marketing_mail_flats', 'USPS Marketing Mail', 'Flats')
 ) AS v(service_id, service_group, service_label)
)
SELECT h.fiscal_year, h.service_id, h.service_group, h.service_label,
 CONCAT(h.service_group, ' | ', h.service_label) AS service_display,
 h.revenue_usd, h.attributable_cost_usd,
 h.revenue_usd - h.attributable_cost_usd AS contribution_before_common_costs_usd,
 h.source_url, h.source_locator, h.source_version, h.source_precision,
 CONVERT(nvarchar(500), 'Candidate exact-label match; product definitions and cost methodology may change. Reported figures are nominal estimates.') AS comparability_note
FROM silver.usps_historical_selected_candidates h
JOIN ServiceMap m ON h.service_id=m.service_id AND h.service_group=m.service_group AND h.service_label=m.service_label
WHERE h.fiscal_year BETWEEN 2018 AND 2023
UNION ALL
SELECT s.fiscal_year, m.service_id, s.service_group, s.service_label,
 CONCAT(s.service_group, ' | ', s.service_label),
 s.revenue_usd, s.attributable_cost_usd, s.contribution_before_common_costs_usd,
 s.source_url, s.source_locator, s.source_version, s.source_precision,
 CONVERT(nvarchar(500), 'Candidate exact-label match; product definitions and cost methodology may change. Reported figures are nominal estimates.')
FROM silver.usps_market_dominant_2024_2025 s
JOIN ServiceMap m ON s.service_group=m.service_group AND s.service_label=m.service_label
WHERE s.fiscal_year IN (2024,2025) AND s.row_type='service';
GO

-- Exploratory revenue-only scenario for FY2026, made as if only FY2018–2025
-- were known. This is a retrospective experiment using FY2018–2025 reports, not a current
-- forecast. WAPE uses only four one-year-ahead tests, FY2022 through FY2025.
-- It does not establish confidence, precision, comparability, or future accuracy.
CREATE OR ALTER VIEW gold.usps_revenue_scenarios_asof_2025 AS
WITH Hist AS (
 SELECT fiscal_year, service_id, service_group, service_label, service_display,
        CONVERT(float, revenue_usd) AS y, CONVERT(float, fiscal_year - 2018) AS x
 FROM gold.usps_four_service_history_2018_2025
 WHERE fiscal_year BETWEEN 2018 AND 2025 AND revenue_usd IS NOT NULL
), Train AS (
 SELECT service_id, MIN(service_group) AS service_group, MIN(service_label) AS service_label,
        MIN(service_display) AS service_display, COUNT(*) AS n,
        MIN(fiscal_year) AS first_year, MAX(fiscal_year) AS last_year,
        SUM(x) AS sx, SUM(x*x) AS sxx, SUM(y) AS sy, SUM(x*y) AS sxy,
        MAX(CASE WHEN fiscal_year=2025 THEN y END) AS last_value
 FROM Hist GROUP BY service_id
), Forecasts AS (
 SELECT service_id, service_group, service_label, service_display, method, revenue_usd
 FROM Train CROSS APPLY (VALUES
  ('Last-year baseline', last_value),
  ('Linear trend', sy/NULLIF(CONVERT(float,n),0) +
   (CONVERT(float,n)*sxy-sx*sy)/NULLIF(CONVERT(float,n)*sxx-sx*sx,0)
   * (8.0-sx/NULLIF(CONVERT(float,n),0)))
 ) p(method,revenue_usd)
 WHERE n=8 AND first_year=2018 AND last_year=2025 AND last_value IS NOT NULL
), TestTrain AS (
 SELECT t.service_id, t.fiscal_year AS test_year, t.y AS actual_y, COUNT(*) AS n,
        SUM(h.x) AS sx, SUM(h.x*h.x) AS sxx, SUM(h.y) AS sy, SUM(h.x*h.y) AS sxy,
        MAX(CASE WHEN h.fiscal_year=t.fiscal_year-1 THEN h.y END) AS last_value,
        CONVERT(float,t.fiscal_year-2018) AS target_x
 FROM Hist t JOIN Hist h ON t.service_id=h.service_id AND h.fiscal_year<t.fiscal_year
 WHERE t.fiscal_year BETWEEN 2022 AND 2025
 GROUP BY t.service_id,t.fiscal_year,t.y
), TestForecasts AS (
 SELECT service_id,test_year,actual_y,method,predicted_y
 FROM TestTrain CROSS APPLY (VALUES
  ('Last-year baseline', last_value),
  ('Linear trend', sy/NULLIF(CONVERT(float,n),0) +
   (CONVERT(float,n)*sxy-sx*sy)/NULLIF(CONVERT(float,n)*sxx-sx*sx,0)
   * (target_x-sx/NULLIF(CONVERT(float,n),0)))
 ) p(method,predicted_y)
 WHERE last_value IS NOT NULL AND n=test_year-2018
), Backtest AS (
 SELECT service_id, method, COUNT(*) AS backtest_points,
        100.0 * SUM(ABS(actual_y-predicted_y))/NULLIF(SUM(ABS(actual_y)),0) AS historical_wape_pct
 FROM TestForecasts GROUP BY service_id, method
)
SELECT f.service_id,f.service_group,f.service_label,f.service_display,
       CONVERT(smallint,2025) AS latest_input_fiscal_year, CONVERT(smallint,2026) AS forecast_year,
       f.method, CONVERT(decimal(19,2), f.revenue_usd) AS revenue_usd,
       b.backtest_points, CONVERT(decimal(9,4),b.historical_wape_pct) AS historical_wape_pct,
       CONVERT(nvarchar(500), 'Retrospective FY2026 illustration using FY2018-FY2025 reports; FY2026 actuals not included; future accuracy not established. Four backtest points; definitions and reporting methods may change.') AS model_note
FROM Forecasts f JOIN Backtest b ON f.service_id=b.service_id AND f.method=b.method
WHERE b.backtest_points=4;
GO
