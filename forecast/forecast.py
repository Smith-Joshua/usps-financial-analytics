"""Compare simple revenue forecasting methods on public USPS annual data.

This retrospective exercise is not a current or operational forecast. It reads
a small, curated CSV; it does not connect to or modify a database.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
from decimal import Decimal, InvalidOperation
from pathlib import Path

HERE = Path(__file__).resolve().parent
YEARS = tuple(range(2018, 2026))
VALIDATION_YEARS = (2022, 2023, 2024)
EVALUATION_YEAR = 2025
SCENARIO_YEAR = 2026
METHODS = ('last_year', 'linear_trend')
SERVICE = 'marketing_mail_flats'
DEFAULT_INPUT = HERE / 'data' / 'usps_revenue_fy2018_2025.csv'


def load_csv(path: Path) -> list[dict]:
    """Read the curated public-data extract and reject malformed values."""
    required = {'year', 'service_id', 'service_group', 'service_label',
                'revenue_usd', 'source_precision'}
    rows = []
    with path.open(newline='', encoding='utf-8') as file:
        reader = csv.DictReader(file)
        missing = required - set(reader.fieldnames or ())
        if missing:
            raise ValueError(f'Missing CSV columns: {", ".join(sorted(missing))}')
        for line_number, row in enumerate(reader, start=2):
            try:
                year = int(row['year'])
                revenue = Decimal(row['revenue_usd'])
                if not revenue.is_finite():
                    raise ValueError('Revenue must be finite.')
            except (ValueError, TypeError, InvalidOperation) as exc:
                raise ValueError(f'Invalid year or revenue on CSV line {line_number}.') from exc
            rows.append(dict(year=year, service_id=row['service_id'],
                             service_group=row['service_group'],
                             service_label=row['service_label'], revenue_usd=revenue,
                             source_precision=row['source_precision']))
    return rows


def prepare_series(rows: list[dict], service_id: str) -> list[tuple[int, Decimal]]:
    selected = [r for r in rows if r['service_id'] == service_id]
    if not selected:
        raise ValueError(f'Unknown or missing service: {service_id}')
    labels = {(r['service_group'], r['service_label']) for r in selected}
    if len(labels) != 1:
        raise ValueError('Conflicting service labels; do not merge these observations.')
    result = sorted((r['year'], r['revenue_usd']) for r in selected)
    if tuple(year for year, _ in result) != YEARS:
        raise ValueError('Expected exactly one observation for every year 2018–2025.')
    if any(value <= 0 for _, value in result):
        raise ValueError('Revenue must be positive for this exercise’s WAPE comparison.')
    return result


def predict(training: list[tuple[int, Decimal]], target: int, method: str) -> Decimal:
    """Forecast target using prior years only; reject accidental future leakage."""
    if len(training) < 2 or any(y >= target for y, _ in training):
        raise ValueError('Use at least two observations strictly before the target year.')
    if len({y for y, _ in training}) != len(training):
        raise ValueError('Duplicate training years.')
    ordered = sorted(training)
    if method == 'last_year':
        if ordered[-1][0] != target - 1:
            raise ValueError('Prior fiscal year required for the last-year baseline.')
        return ordered[-1][1]
    if method == 'linear_trend':
        # The offsets and Decimal arithmetic avoid loss of precision from large years.
        xs = [Decimal(y - 2018) for y, _ in ordered]
        ys = [v for _, v in ordered]
        xbar, ybar = sum(xs) / len(xs), sum(ys) / len(ys)
        denominator = sum((x - xbar) ** 2 for x in xs)
        if not denominator:
            raise ValueError('Need at least two distinct years.')
        slope = sum((x - xbar) * (y - ybar) for x, y in zip(xs, ys)) / denominator
        return ybar + slope * (Decimal(target - 2018) - xbar)
    raise ValueError(f'Unsupported method: {method}')


def wape(pairs: list[tuple[Decimal, Decimal]]) -> Decimal:
    if not pairs:
        raise ValueError('WAPE requires observations.')
    denominator = sum(abs(actual) for actual, _ in pairs)
    if denominator == 0:
        raise ValueError('Cannot calculate WAPE when all actual values are zero.')
    return sum(abs(actual - forecast) for actual, forecast in pairs) / denominator * 100


def run_experiment(series: list[tuple[int, Decimal]]) -> dict:
    data = dict(series)
    trials = []
    for year in (*VALIDATION_YEARS, EVALUATION_YEAR):
        training = [(y, v) for y, v in series if y < year]
        for method in METHODS:
            estimate = predict(training, year, method)
            stage = 'validation' if year in VALIDATION_YEARS else 'later_evaluation'
            trials.append(dict(year=year, stage=stage,
                               training_first=training[0][0], training_last=training[-1][0],
                               method=method, actual_usd=data[year], forecast_usd=estimate,
                               absolute_error_usd=abs(data[year] - estimate)))
    # Choose a method using only the earlier validation years, never FY2025.
    scores = {}
    for method in METHODS:
        validation_pairs = [(trial['actual_usd'], trial['forecast_usd']) for trial in trials
                            if trial['stage'] == 'validation' and trial['method'] == method]
        scores[method] = wape(validation_pairs)
    # Deterministic tie break prefers the simpler baseline.
    chosen = min(METHODS, key=lambda m: (scores[m], METHODS.index(m)))
    later = next(r for r in trials if r['year'] == EVALUATION_YEAR and r['method'] == chosen)
    scenario = predict(series, SCENARIO_YEAR, chosen)
    return dict(validation_wape_percent=scores, selected_method=chosen,
                selected_later_evaluation=later, scenario_2026_usd=scenario, trials=trials)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--service', default=SERVICE, help='Exact service_id from the input CSV')
    parser.add_argument('--input', type=Path, default=DEFAULT_INPUT,
                        help='Curated annual revenue CSV (default: bundled data)')
    parser.add_argument('--output', type=Path, default=HERE / 'output',
                        help='Directory for generated results (default: forecast/output)')
    args = parser.parse_args()
    rows = load_csv(args.input)
    series = prepare_series(rows, args.service)
    experiment = run_experiment(series)
    selected = next(r for r in rows if r['service_id'] == args.service)
    canonical = json.dumps([{'year': y, 'revenue_usd': str(v)} for y, v in series],
                           sort_keys=True, separators=(',', ':'))
    out = args.output
    out.mkdir(parents=True, exist_ok=True)
    summary = dict(status='retrospective practice, not an operational forecast',
                   source=f'Curated USPS annual revenue CSV: {args.input.name}',
                   service_id=args.service, service_group=selected['service_group'],
                   service_label=selected['service_label'], observations=len(series),
                   input_sha256=hashlib.sha256(canonical.encode()).hexdigest(),
                   validation_years=VALIDATION_YEARS, later_evaluation_year=EVALUATION_YEAR,
                   later_evaluation_note='2025 was used only after method selection in this script, but was already inspected in earlier project work; it is not independent fresh validation.',
                   scenario_note='Illustrative retrospective FY2026 estimate using FY2018–2025 reports; FY2026 has ended and no 2026 product actuals are included.',
                   caveats=['Only 8 annual observations and 3 validation points per method.',
                            'Service naming matches do not prove comparable definitions.',
                            'Reported revenues are nominal estimates; reporting and cost methodology changed.',
                            'Model forecasts revenue, not net profit; common costs and non-additivity are not resolved.',
                            'WAPE and one later evaluation cannot establish future accuracy.'],
                   validation_wape_percent=experiment['validation_wape_percent'],
                   selected_method=experiment['selected_method'],
                   selected_later_evaluation=experiment['selected_later_evaluation'],
                   scenario_2026_usd=experiment['scenario_2026_usd'])
    (out / 'summary.json').write_text(json.dumps(summary, indent=2, default=str) + '\n', encoding='utf-8')
    with (out / 'backtest.csv').open('w', newline='', encoding='utf-8') as file:
        writer = csv.DictWriter(file, fieldnames=list(experiment['trials'][0]))
        writer.writeheader()
        writer.writerows(experiment['trials'])
    print(f"Service: {selected['service_group']} / {selected['service_label']}")
    print('Validation FY2022-FY2024 WAPE:')
    for method, score in experiment['validation_wape_percent'].items():
        print(f'  {method}: {score:.2f}%')
    print(f"Selected method: {experiment['selected_method']}")
    print(f"FY2025 later evaluation actual: ${experiment['selected_later_evaluation']['actual_usd']/Decimal(1_000_000):,.1f}m")
    print(f"FY2025 later evaluation forecast: ${experiment['selected_later_evaluation']['forecast_usd']/Decimal(1_000_000):,.1f}m")
    print(f"FY2026 retrospective scenario: ${experiment['scenario_2026_usd']/Decimal(1_000_000):,.1f}m")
    print('Practice only: only 8 annual records; 2025 was seen in earlier work; forecasting assumptions may not hold.')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as exc:
        print(f'Forecast not run: {exc}', file=sys.stderr)
        raise SystemExit(1)
