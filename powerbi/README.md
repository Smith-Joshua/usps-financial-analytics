# Power BI report source

`USPS Pilot.pbip` is the reviewed local Power BI project. Its adjacent `.Report` and `.SemanticModel` folders contain the report layout and semantic model as text-based project files. Local `.pbi` caches, machine settings and credentials are excluded.

The report uses DirectQuery to three gold views in a local SQL Server database named `USPSProfitabilityPilot`. **The database and data are not bundled here.** Opening the PBIP on another computer therefore requires a compatible Windows Power BI Desktop installation, SQL Server, the expected database and views, appropriate credentials, and a trusted connection. The SQL folder documents selected transformations, but does not independently rebuild the data source.

The five pages cover FY2025 service contribution and detail, FY2018–FY2025 historical comparisons for four services, and retrospective FY2026 revenue scenarios. Contribution excludes common costs and is not net profit. The scenarios are illustrative, not current forecasts.

The reviewed local design adds descriptions, alt text, chart sorting, colors and reading-order improvements. Its three DirectQuery tables were reviewed without relationships; fields should not be assumed to filter across those tables. The privately published online report uses an earlier design and is not a public interactive demo. Review a static preview in the main project materials when a configured database is unavailable.
