# SQL transformations

These SQL Server scripts document the warehouse logic behind the report. They are included for review, not as a complete one-command database installer.

- `02-create-schemas.sql` creates the bronze, silver, and gold schemas in a new database.
- `09-medallion.sql` stores or compares 88 selected extracted records in bronze, derives silver views, and reconciles temporary rebuilds with the existing silver tables. It expects a parameterized `@payload`, pre-existing silver table definitions, and a surrounding transaction supplied by the original loader.
- `07-create-fy2025-report-view.sql` defines the 2025 service-level report view from an existing gold service-detail view.
- `08-create-history-scenarios.sql` defines the four-service history view and retrospective revenue scenario calculations. The history view depends on two existing silver tables.

The original local workflow also includes a source extractor, reviewed extracts and original source documents, table setup, and a PowerShell loader. Those dependencies are not all redistributed here. Consequently, **these files alone cannot rebuild the warehouse or populate the report**. They were developed for SQL Server and use its JSON, temporary-table, transaction, and `GO` batch syntax; they are not portable SQL for other database engines.

The source data are published estimates. Attributable costs and published totals can overlap, so summing service costs does not necessarily reproduce a class total. Contribution is revenue less attributable cost, before common costs; it is not net profit. Historical labels and costing methods can change between years.

The FY2026 scenarios are retrospective illustrations based on FY2018–FY2025 data. Four historical tests are insufficient to establish forecast reliability, and no FY2026 service actuals are included.
