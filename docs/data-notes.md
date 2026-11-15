# Data, definitions and validation

## Scope and provenance

This is a selected analytical extract from USPS Cost and Revenue Analysis publications. It is not transaction, customer or order-level data and does not represent the entire organization. The working pipeline traced 64 FY2024–FY2025 market-dominant records and 24 older service records to locally preserved originals. The reporting history selects four services over FY2018–FY2025.

- [USPS FY2025 Cost and Revenue Analysis](https://about.usps.com/what/financials/cost-revenue-analysis-reports/fy2025.pdf)
- [USPS FY2024 revised Cost and Revenue Analysis](https://about.usps.com/what/financials/cost-revenue-analysis-reports/fy2024.pdf)
- [FY2025 regulatory source filing](https://prc.arkcase.com/api/prc-dockets/filing/downloadFile?fileId=250695&inline=false)
- [USPS source-material rights and permissions](https://about.usps.com/what/business-services/rights-permissions/)

Original reports remain with their publishers. Numeric extracts and independently generated project code are included only where indicated; external source material retains its own rights. No claim is made that all USPS material is in the public domain.

## Financial meaning

**Contribution before common costs = revenue − attributable cost.** It is not net profit. Attributable costs need not include organization-wide overhead, and published group cost totals need not equal the sum of service costs. Totals or fees can overlap individual rows.

Values are nominal source estimates. The FY2024 PDF uses a coarser reporting precision than the FY2025 workbook. Displayed cents in derived calculations do not imply cent-level accuracy. Cost methodology changed for affected services in FY2020, FY2024 and FY2025; matching labels alone do not establish unchanged service definitions. Trend differences are not causal evidence.

## Checks and limits

- The local bronze-to-silver loader rebuilt selected rows into temporary tables, reconciled them to existing silver data and rolled back a changed-input mismatch. It is scoped to reviewed source layouts, not arbitrary future reports.
- FY2025 report detail, historical series and scenario views were checked for expected row counts and contribution arithmetic. The Power BI model deliberately leaves unsupported multi-service totals blank.
- Selected online figures matched SQL, and manual visual refresh succeeded. A gateway query approximately 30 minutes after page selection is consistent with automatic page refresh; the observation did not isolate all possible user activity or test a changed source value.
- A separate five-test Python suite checked forecast logic. Its validation uses three FY2022–FY2024 years, followed by a FY2025 check that is not a fresh holdout because that year was previously examined. FY2026 is a retrospective scenario, not a current outlook.
- The source watcher archives and indexes documents for human review; it does not automatically ingest new financial rows. The published report uses an earlier layout than the reviewed local PBIP source.
