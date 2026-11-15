"""Behavior and reproducibility checks for the public CSV workflow."""
import json
import csv
import subprocess
import sys
import tempfile
import unittest
from decimal import Decimal as D
from pathlib import Path
from forecast import DEFAULT_INPUT, load_csv, predict, wape, prepare_series, run_experiment


class ForecastChecks(unittest.TestCase):
    def test_baseline_and_linear_known_examples(self):
        rows = [(2020, D('100')), (2021, D('110')), (2022, D('120'))]
        self.assertEqual(predict(rows, 2023, 'last_year'), D('120'))
        self.assertEqual(predict(rows, 2023, 'linear_trend'), D('130'))

    def test_future_data_is_rejected(self):
        with self.assertRaises(ValueError):
            predict([(2023, D('100')), (2024, D('110'))], 2024, 'linear_trend')

    def test_wape_uses_total_absolute_error(self):
        self.assertEqual(wape([(D('100'), D('90')), (D('200'), D('220'))]), D('10'))
        with self.assertRaises(ValueError):
            wape([(D('0'), D('1'))])

    def test_duplicate_missing_and_nonpositive_rejected(self):
        rows = [dict(service_id='x', service_group='A', service_label='B',
                     year=y, revenue_usd=D('100')) for y in range(2018, 2026)]
        self.assertEqual(len(prepare_series(rows, 'x')), 8)
        with self.assertRaises(ValueError):
            prepare_series(rows + [rows[0]], 'x')
        with self.assertRaises(ValueError):
            prepare_series(rows[:-1], 'x')
        rows[0]['revenue_usd'] = D('0')
        with self.assertRaises(ValueError):
            prepare_series(rows, 'x')

    def test_later_value_cannot_influence_model_selection(self):
        first = [(year, D(100 + (year-2018)*10)) for year in range(2018, 2026)]
        changed = first[:-1] + [(2025, D('999999'))]
        a, b = run_experiment(first), run_experiment(changed)
        self.assertEqual(a['selected_method'], b['selected_method'])
        self.assertEqual(a['validation_wape_percent'], b['validation_wape_percent'])
        self.assertEqual(a['selected_later_evaluation']['forecast_usd'], b['selected_later_evaluation']['forecast_usd'])

    def test_public_extract_has_four_complete_attributed_series(self):
        rows = load_csv(DEFAULT_INPUT)
        self.assertEqual(len(rows), 32)
        service_ids = {row['service_id'] for row in rows}
        self.assertEqual(len(service_ids), 4)
        for service_id in service_ids:
            self.assertEqual(len(prepare_series(rows, service_id)), 8)
        with DEFAULT_INPUT.open(encoding='utf-8', newline='') as file:
            source_rows = list(csv.DictReader(file))
        for row in source_rows:
            self.assertTrue(row['source_url'].startswith('https://'))
            self.assertTrue(row['source_locator'])
            self.assertTrue(row['source_version'])
            self.assertTrue(row['source_precision'])

    def test_rejects_nonfinite_revenue(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'bad.csv'
            path.write_text('year,service_id,service_group,service_label,revenue_usd,source_precision\n'
                            '2025,x,A,B,NaN,estimate\n', encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'Invalid year or revenue'):
                load_csv(path)

    def test_cli_reproduces_flats_results_from_another_directory(self):
        script = Path(__file__).resolve().with_name('forecast.py')
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / 'results'
            run = subprocess.run([sys.executable, str(script), '--output', str(output)],
                                 cwd=temporary, text=True, capture_output=True, check=True)
            result = json.loads((output / 'summary.json').read_text(encoding='utf-8'))
            self.assertEqual(result['selected_method'], 'last_year')
            self.assertEqual(result['observations'], 8)
            self.assertAlmostEqual(float(result['validation_wape_percent']['last_year']), 4.56, places=2)
            self.assertAlmostEqual(float(result['validation_wape_percent']['linear_trend']), 11.39, places=2)
            self.assertIn('not independent fresh validation', result['later_evaluation_note'])
            self.assertIn('retrospective', run.stdout.lower())
            self.assertTrue((output / 'backtest.csv').is_file())


if __name__ == '__main__': unittest.main()
