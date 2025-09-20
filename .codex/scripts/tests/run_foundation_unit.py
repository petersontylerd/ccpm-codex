#!/usr/bin/env python3
import argparse
import shutil
import subprocess
import tempfile
from contextlib import contextmanager
from pathlib import Path
import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
PLAN_DIR = REPO_ROOT / '.codex' / 'product-plan'
SCRIPT_DIR = REPO_ROOT / '.codex' / 'scripts'


@contextmanager
def plan_backup() -> None:
    backup_dir = Path(tempfile.mkdtemp()) / 'product-plan'
    shutil.copytree(PLAN_DIR, backup_dir)
    try:
        yield
    finally:
        if PLAN_DIR.exists():
            shutil.rmtree(PLAN_DIR)
        shutil.copytree(backup_dir, PLAN_DIR)
        shutil.rmtree(backup_dir.parent)


def run_script(script_name: str, *args: str) -> None:
    script = SCRIPT_DIR / 'plan' / script_name
    subprocess.run(['bash', str(script), *args], check=True, cwd=REPO_ROOT)


def prd_update() -> None:
    with plan_backup():
        run_script('prd-update.sh',
                   '--product-name', 'Unit Test',
                   '--project-code', 'UNIT-001',
                   '--summary', 'Unit summary',
                   '--goal', 'G1')
        data = yaml.safe_load((PLAN_DIR / 'foundation' / 'prd.yaml').read_text())
        assert data['metadata']['product_name'] == 'Unit Test'
        assert 'G1' in data['overview']['goals']


def personas_update() -> None:
    with plan_backup():
        payload = {
            'primary_personas': [
                {'id': 'P-UT', 'name': 'Unit Tester', 'role': 'QA'}
            ]
        }
        payload_path = Path(tempfile.mkstemp(suffix='.yaml')[1])
        payload_path.write_text(yaml.safe_dump(payload))
        try:
            run_script('personas-update.sh', '--input', str(payload_path))
        finally:
            payload_path.unlink(missing_ok=True)
        data = yaml.safe_load((PLAN_DIR / 'foundation' / 'personas.yaml').read_text())
        assert any(p.get('id') == 'P-UT' for p in data['primary_personas'])


def strategy_update() -> None:
    with plan_backup():
        payload = {
            'strategic_goals': [
                {'id': 'SG-UT', 'description': 'Unit goal', 'time_horizon': 'short-term'}
            ]
        }
        payload_path = Path(tempfile.mkstemp(suffix='.yaml')[1])
        payload_path.write_text(yaml.safe_dump(payload))
        try:
            run_script('strategy-update.sh', '--input', str(payload_path))
        finally:
            payload_path.unlink(missing_ok=True)
        data = yaml.safe_load((PLAN_DIR / 'foundation' / 'strategy.yaml').read_text())
        assert any(g.get('id') == 'SG-UT' for g in data['strategic_goals'])


def roadmap_update() -> None:
    with plan_backup():
        payload = {
            'time_horizons': {
                'short_term': {
                    'goals': ['SG-UT-RM'],
                    'milestones': [
                        {
                            'id': 'M-UT-01',
                            'description': 'Validate roadmap updater',
                            'key_outcome': 'Roadmap automation verified',
                        }
                    ],
                }
            },
            'risks_assumptions': [
                {
                    'id': 'RM-UT-01',
                    'description': 'Roadmap script regression',
                    'mitigation': 'Covered by unit test',
                }
            ],
        }
        payload_path = Path(tempfile.mkstemp(suffix='.yaml')[1])
        payload_path.write_text(yaml.safe_dump(payload))
        try:
            run_script('roadmap-update.sh', '--input', str(payload_path))
        finally:
            payload_path.unlink(missing_ok=True)
        data = yaml.safe_load((PLAN_DIR / 'foundation' / 'roadmap.yaml').read_text())
        short_term = data['time_horizons']['short_term']
        assert 'SG-UT-RM' in short_term.get('goals', [])
        assert any(m.get('id') == 'M-UT-01' for m in short_term.get('milestones', []))
        assert any(r.get('id') == 'RM-UT-01' for r in data.get('risks_assumptions', []))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.parse_args()
    prd_update()
    personas_update()
    strategy_update()
    roadmap_update()


if __name__ == '__main__':
    main()
