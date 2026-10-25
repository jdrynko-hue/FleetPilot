"""Offline refusal checks for the CI provisioner; never starts PostgreSQL."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tools/run_garage_progress_ci.sh'


class CiGuards(unittest.TestCase):
    def refused(self, overrides, args=()):
        env = dict(PATH='/nonexistent', GITHUB_ACTIONS='true', CI='true',
            RUNNER_ENVIRONMENT='github-hosted', RUNNER_OS='Linux',
            GITHUB_REPOSITORY='jdrynko-hue/FleetPilot', GARAGE_NATIVE_DISPOSABLE='1')
        env.update(overrides)
        # No id/postgres/gosu/mktemp executable is available in this test PATH.
        # A correct refusal must occur using Bash builtins before provisioning.
        result = subprocess.run(['/bin/bash', str(SCRIPT), *args], env=env,
            text=True, capture_output=True, timeout=3)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn('REFUSED:',result.stderr)
        self.assertNotIn('command not found',result.stderr)
        self.assertEqual(result.stdout,'')

    def test_work_sandbox_is_refused_before_commands(self):
        self.refused({'GITHUB_ACTIONS':''})

    def test_missing_ci_flag_is_refused(self):
        self.refused({'CI':'false'})

    def test_self_hosted_runner_is_refused(self):
        self.refused({'RUNNER_ENVIRONMENT':'self-hosted'})

    def test_other_repository_is_refused(self):
        self.refused({'GITHUB_REPOSITORY':'another/repository'})

    def test_non_linux_job_is_refused(self):
        self.refused({'RUNNER_OS':'Windows'})

    def test_no_explicit_fixture_opt_in_is_refused(self):
        self.refused({'GARAGE_NATIVE_DISPOSABLE':'0'})

    def test_external_connection_arguments_are_refused(self):
        self.refused({}, ['--host=example.com'])

    def test_both_shell_programs_parse_without_execution(self):
        outer = subprocess.run(['/bin/bash','-n',str(SCRIPT)], capture_output=True)
        self.assertEqual(outer.returncode,0,outer.stderr)
        inner = SCRIPT.read_text().split("<<'NATIVE'\n",1)[1].rsplit('\nNATIVE',1)[0]
        result = subprocess.run(['/bin/bash','-n'], input=inner,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr)


if __name__ == '__main__':
    unittest.main()
