# Retrospective USPS revenue forecasting

This reproducible Python exercise compares two transparent forecasting baselines using eight annual observations for each of four USPS services. It forecasts **revenue**, not profit, and demonstrates evaluation mechanics rather than an operational forecast.

## Run

Python 3.10 or newer is the only requirement. From the repository root:

```bash
python forecast/forecast.py
python -m unittest discover -s forecast -v
```

The default example uses USPS Marketing Mail Flats. To run another series:

```bash
python forecast/forecast.py --service presort_letters
```

The available IDs are `marketing_mail_flats`, `presort_letters`, `single_piece_letters`, and `single_piece_postcards`. The script writes `summary.json` and `backtest.csv` to `forecast/output/`, replacing those generated files on each run. Use `--output PATH` to choose another directory. This standalone example uses the included CSV and does not need SQL Server, Power BI, network access, or third-party Python packages.

## Method

1. Compare a **last-year baseline** and a **linear trend** using one-year-ahead predictions for FY2022 through FY2024. Each prediction uses only earlier years.
2. Compute weighted absolute percentage error (**WAPE**): total absolute error divided by total absolute actual revenue. Select the method with lower validation WAPE, breaking a tie in favor of the baseline.
3. Apply the selected method to FY2025 as a later evaluation, then fit through FY2025 to produce an illustrative **FY2026 retrospective scenario**.

For Marketing Mail Flats, the baseline's FY2022–FY2024 WAPE is **4.56%** versus **11.39%** for the linear trend. The selected baseline projects **$1,184.5 million** for FY2025 against **$1,129.6 million** reported, an absolute difference of approximately **$54.9 million**. The FY2026 retrospective baseline is approximately **$1,129.6 million**.

The FY2025 value was excluded from method selection in this script, but it had been inspected in prior project work and is **not a fresh independent holdout**. FY2026 has ended, and the FY2026 service actual is not included here; the scenario is **not a current forecast**. These three validation years and one later evaluation cannot establish predictive reliability.

## Data and limitations

[`data/usps_revenue_fy2018_2025.csv`](data/usps_revenue_fy2018_2025.csv) contains **32 curated service-year observations** selected from the project's SQL reporting view. Each row includes the official source URL, locator, revision/version, and reported precision. FY2018–FY2024 observations come from [USPS annual cost and revenue reports](https://about.usps.com/what/financials/cost-revenue-analysis-reports/); FY2025 comes from the [public FY2025 workbook](https://prc.arkcase.com/api/prc-dockets/filing/downloadFile?fileId=250695&inline=false). Revenue amounts are nominal reported estimates; digits in the workbook do not imply certainty to the cent.

Matching service names across years does not establish unchanged definitions. The Postal Regulatory Commission describes relevant methodology changes in its [FY2024 financial analysis](https://www.prc.gov/sites/default/files/reports/FY-2024-Financial-Report_Final.pdf) and [FY2025 annual compliance determination](https://www.prc.gov/sites/default/files/reports/Annual%20Compliance%20determination.pdf). The FY2025 CRA preface mentions an exception whose specific implications for these selected rows remain unresolved. The exercise does not model common costs, inflation, uncertainty intervals, price, volume, or other business drivers, and it cannot show why revenue changed.

The eight behavioral and integration tests cover time ordering, evaluation leakage, WAPE, malformed inputs, the complete data extract, and reproducible CLI output. They check this implementation; they are not evidence of business impact or future forecast performance.
