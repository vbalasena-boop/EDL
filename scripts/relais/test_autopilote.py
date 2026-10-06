"""Contrats CI testés sans GitHub, secret réel, commit ni push."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


class AutopiloteTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        shutil.copytree(ROOT / 'scripts/relais', self.root / 'scripts/relais', ignore=shutil.ignore_patterns('__pycache__'))
        shutil.copytree(ROOT / '.relais', self.root / '.relais')
        (self.root / '.relais/verifier').write_text('true\n')
        self.artifacts = self.root / '_bmad-output/implementation-artifacts'
        self.artifacts.mkdir(parents=True)
        self.status = self.artifacts / 'sprint-status.yaml'
        self.status.write_text('development_status:\n  epic-6: in-progress\n  6-1: ready-for-dev\n')
        self.fiche = self.artifacts / 'spec-6-1.md'
        self.fiche.write_text('# Story\n\n**Agent :** codex\n**Niveau :** simple\n\n## Reprise\n\nÀ faire.\n')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.runner = self.root / 'runner'
        self.runner.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'], RUNNER_TEMP=str(self.runner),
                        RELAIS_STATUT=str(self.status), GITHUB_REPOSITORY='test/repo', GITHUB_RUN_ID='42',
                        GITHUB_TOKEN='fake-github', GH_TOKEN='fake-github', GITHUB_WORKSPACE=str(self.root),
                        DECLENCHEUR='manuel', POUR='codex', PROFONDEUR='0', STORY='',
                        MOCK_LOG=str(self.root / 'calls'), MOCK_BOARD='[]')
        for k in ('GITHUB_OUTPUT', 'CODEX_AUTH_JSON', 'RELAIS_PAT', 'MODE', 'MODELE', 'AUTH_KO', 'QUOTA_ATTEINT'):
            self.env.pop(k, None)
        self.executable('gh', '''#!/usr/bin/env python3
import os,sys
from pathlib import Path
a=sys.argv[1:]
with open(os.environ['MOCK_LOG'],'a') as f: f.write('gh '+repr(a)+'\\n')
if a[:2]==['issue','list']:
    print(os.environ.get('MOCK_BOARD','[]') if 'relais-tableau' in a else '')
elif a[:2]==['repo','view']: print('main')
elif a[:2]==['secret','set']:
    Path(os.environ['RUNNER_TEMP'],'saved-secret').write_text(sys.stdin.read())
''')
        self.executable('git', '''#!/usr/bin/env python3
import os,sys
with open(os.environ['MOCK_LOG'],'a') as f: f.write('git '+repr(sys.argv[1:])+'\\n')
a=sys.argv[1:]
if a[0]=='log': print(os.environ.get('MOCK_COMMIT',''))
elif a[0]=='status': print(os.environ.get('MOCK_DIRTY',''),end='')
elif a[:2]==['diff','--name-only']: print(os.environ.get('MOCK_FILES','').replace('|','\\0'),end='\\0')
elif a[:2]==['ls-files','--others']: print(os.environ.get('MOCK_UNTRACKED','').replace('|','\\0'),end='\\0')
elif a[:2]==['rev-parse','--git-path']: print('/nonexistent/merge-head')
elif a[:2]==['diff','--cached']: sys.exit(1)
''')
        self.executable('codex', '''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
p=Path(os.environ['CODEX_HOME'])
assert (p/'auth.json').stat().st_mode & 0o777 == 0o600
assert not any(os.environ.get(k) for k in ['CODEX_AUTH_JSON','RELAIS_PAT','GH_TOKEN','GITHUB_TOKEN'])
if os.environ.get('MOCK_ROTATE'): (p/'auth.json').write_text('rotated-fake-auth')
d=p/'sessions/2026/01/01'; d.mkdir(parents=True)
(d/'rollout-1.jsonl').write_text(json.dumps({'type':'event_msg','payload':{'type':'token_count','rate_limits':{'primary':{'used_percent':96,'resets_at':2000000000}}}})+'\\n')
print(os.environ.get('MOCK_CODEX_TEXT','ok'))
sys.exit(int(os.environ.get('MOCK_CODEX_EXIT','0')))
''')

    def executable(self, nom, texte):
        p = self.bin / nom
        p.write_text(texte)
        p.chmod(0o755)

    def run_script(self, commande, **env):
        result = subprocess.run(['bash', 'scripts/relais/autopilote.sh', commande], cwd=self.root,
                                env=dict(self.env, **env), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def decide(self, **env):
        return self.run_script('decider', **env)

    def test_decider_local_et_output(self):
        sortie = self.decide(GH_TOKEN='', GITHUB_TOKEN='', GITHUB_REPOSITORY='')
        self.assertIn('go=true', sortie)
        self.assertIn('story=6-1', sortie)
        self.assertIn('modele=gpt-5.5', sortie)
        output = self.root / 'output'
        self.assertEqual(self.decide(GITHUB_OUTPUT=str(output)), '')
        self.assertIn('go=true', output.read_text())

    def test_decider_stops(self):
        self.assertIn('raison=chaine-max', self.decide(PROFONDEUR='12'))
        body = f'<!-- reprise_codex_apres={int(time.time()) + 3600} -->'
        self.assertIn('raison=quota-codex', self.decide(MOCK_BOARD=json.dumps([{'body': body, 'number': 1}])))
        self.assertIn('raison=claude-actif', self.decide(DECLENCHEUR='schedule', MOCK_COMMIT=str(int(time.time()))))

    def test_decider_planification_revue_et_tous(self):
        self.status.write_text('development_status:\n  epic-6: in-progress\n  6-1: done\n')
        self.assertIn('mode=planifier', self.decide())
        self.status.write_text('development_status:\n  epic-6: done\n  6-1: done\n')
        self.assertIn('raison=rien-a-faire', self.decide())
        self.status.write_text('development_status:\n  6-1: review\n  6-2: ready-for-dev\n')
        self.fiche.write_text('Agent: Codex\n')
        body = f'<!-- pour_tous_jusqua={int(time.time()) + 3600} -->'
        sortie = self.decide(MOCK_BOARD=json.dumps([{'body': body, 'number': 1}]))
        self.assertIn('pour=tous', sortie)
        self.assertIn('mode=revue', sortie)

    def test_codex_rotation_et_nettoyage(self):
        self.decide()
        secret = base64.b64encode(b'fake-auth-only').decode()
        out = self.run_script('codex', CODEX_AUTH_JSON=secret, MOCK_ROTATE='1')
        self.assertIn('codex_ok=true', out)
        self.assertIn('cinq_heures=96', out)
        self.assertNotIn(secret, out)
        self.run_script('sauver-auth', RELAIS_PAT='fake-pat')
        self.assertEqual(base64.b64decode((self.runner / 'saved-secret').read_text()), b'rotated-fake-auth')
        self.assertFalse((self.runner / 'codex').exists())

    def test_codex_sans_secret_et_quota(self):
        self.decide()
        self.assertIn('alerte_auth=secret-manquant', self.run_script('codex'))
        sortie = self.run_script('codex', CODEX_AUTH_JSON=base64.b64encode(b'fake').decode(), MOCK_CODEX_EXIT='1', MOCK_CODEX_TEXT='hit your usage limit; refresh token')
        self.assertIn('quota_atteint=true', sortie)
        self.assertIn('auth_ko=true', sortie)
        self.run_script('sauver-auth')
        self.assertFalse((self.runner / 'codex').exists())

    def test_auth_pat_manquant(self):
        self.decide()
        self.run_script('codex', CODEX_AUTH_JSON=base64.b64encode(b'fake').decode(), MOCK_ROTATE='1')
        self.assertIn('alerte_auth=pat-manquant', self.run_script('sauver-auth'))
        self.assertFalse((self.runner / 'codex').exists())

    def test_publier_direct_et_revue_vide(self):
        self.decide()
        self.run_script('marquer')
        self.assertIn('in-progress', self.status.read_text())
        self.run_script('publier', CODEX_OK='true', MOCK_DIRTY=' M src/page.tsx', MOCK_FILES='src/page.tsx')
        self.assertIn('6-1: review', self.status.read_text())
        self.decide()
        self.run_script('publier', CODEX_OK='true')
        self.assertIn('6-1: done', self.status.read_text())
        self.assertNotIn("'pr', 'create'", (self.root / 'calls').read_text())

    def test_publier_sensible_pr(self):
        self.decide()
        self.run_script('publier', CODEX_OK='true', MOCK_DIRTY='?? db/new.sql', MOCK_UNTRACKED='db/new.sql')
        self.assertIn('6-1: review', self.status.read_text())
        self.assertIn('claude', self.fiche.read_text())
        calls = (self.root / 'calls').read_text()
        self.assertIn("'--draft'", calls)
        self.assertIn('autopilote/6-1-42', calls)

    def test_publier_echec_et_quota_sans_diff(self):
        self.decide()
        self.run_script('publier', CODEX_OK='false', MOCK_DIRTY=' M code')
        self.assertIn('échec 1', self.fiche.read_text())
        self.run_script('publier', CODEX_OK='false', MOCK_DIRTY=' M code')
        self.assertIn('échec 2', self.fiche.read_text())
        self.assertIn('claude', self.fiche.read_text())
        self.assertIn('6-1: ready-for-dev', self.status.read_text())
        self.run_script('publier', QUOTA_ATTEINT='true')
        self.assertIn('6-1: ready-for-dev', self.status.read_text())

    def test_publier_verification_en_echec(self):
        self.decide()
        (self.root / '.relais/verifier').write_text('echo controle-en-echec; exit 3\n')
        sortie = self.run_script('publier', CODEX_OK='true', MOCK_DIRTY=' M code')
        self.assertIn('verification_ok=false', sortie)
        self.assertIn('6-1: ready-for-dev', self.status.read_text())
        self.assertIn('controle-en-echec', (self.runner / 'pr.md').read_text())
        self.assertIn("'--draft'", (self.root / 'calls').read_text())

    def test_auth_sauvegarde_echouee_nettoie(self):
        self.decide()
        self.run_script('codex', CODEX_AUTH_JSON=base64.b64encode(b'fake').decode(), MOCK_ROTATE='1')
        self.executable('gh', '#!/usr/bin/env bash\nexit 1\n')
        sortie = self.run_script('sauver-auth', RELAIS_PAT='fake-pat')
        self.assertIn('alerte_auth=sauvegarde-echouee', sortie)
        self.assertFalse((self.runner / 'codex').exists())

    def test_tableau_et_enchainement(self):
        self.decide()
        self.run_script('tableau', DECLENCHEUR='relais', CINQ_HEURES='96', RESET_CINQ='2000000000', AUTH_KO='true', ALERTE_AUTH='pat-manquant')
        texte = (self.runner / 'tableau.md').read_text()
        self.assertIn('reprise_codex_apres=2000000000', texte)
        self.assertIn('pour_tous_jusqua=', texte)
        self.assertIn('connexion-codex-ci.sh', texte)
        self.assertRegex(texte, r'CE?ST|CET')
        self.run_script('enchainer')
        self.assertIn("'workflow', 'run'", (self.root / 'calls').read_text())
        avant = (self.root / 'calls').read_text()
        self.run_script('enchainer', QUOTA_ATTEINT='true')
        self.assertEqual(avant, (self.root / 'calls').read_text())

    def test_verifier_premier_echec(self):
        (self.root / '.relais/verifier').write_text('# commentaire\n\nprintf "erreur controle"; exit 7\ntouch ne-pas-creer\n')
        result = subprocess.run(['bash', 'scripts/relais/verifier.sh'], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 7)
        self.assertIn('erreur controle', result.stderr)
        self.assertFalse((self.root / 'ne-pas-creer').exists())


if __name__ == '__main__':
    unittest.main()
