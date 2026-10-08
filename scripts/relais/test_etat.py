import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

import etat


class EtatTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.status = self.root / 'sprint-status.yaml'
        self.env = patch.dict(os.environ, {'RELAIS_STATUT': str(self.status)})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.status.write_text('development_status:\n  epic-6: in-progress\n  6-1: ready-for-dev # garder\n  6-2: done\naction_items:\n  - id: x\n    status: in-progress\n')
        self.fiche('6-1')
        self.fiche('6-2')

    def fiche(self, cle, entete='**Agent :** Codex\n**Niveau :** simple'):
        p = self.root / f'spec-{cle}.md'
        p.write_text('# Story\n' + entete + '\n\n## Reprise\n')
        return p

    def test_bloc_et_commentaire(self):
        self.assertEqual(etat.stories(), {'6-1': 'ready-for-dev', '6-2': 'done'})
        self.assertNotIn('status', etat.etats())

    def test_fiche_exacte_prefixe_ambiguite(self):
        self.assertEqual(etat.fiche('6-1'), self.root / 'spec-6-1.md')
        self.assertEqual(etat.fiche('6-1-long'), self.root / 'spec-6-1.md')
        self.fiche('6-3-long')
        self.assertEqual(etat.fiche('6-3').name, 'spec-6-3-long.md')
        self.fiche('6-3-autre')
        with self.assertRaises(ValueError): etat.fiche('6-3')
        with self.assertRaises(ValueError): etat.fiche('inconnue')

    def test_formes_meta_et_agent(self):
        for forme in ('**Agent :** Claude', 'Agent: Claude', '- Agent : claude', '**Agent** : Claude'):
            with self.subTest(forme=forme):
                p = self.fiche('6-1', forme + '\n- Niveau : MOYEN')
                self.assertEqual(etat.meta('6-1')['agent'], 'claude')
                self.assertEqual(etat.meta('6-1')['modele'], 'gpt-6-sol')
                etat.passer('6-1', 'review', 'autopilote')
                self.assertIn(forme.replace('Claude', 'autopilote').replace('claude', 'autopilote'), p.read_text())
        self.fiche('6-1', '')
        self.assertEqual(etat.meta('6-1')['modele'], 'gpt-6-astra')
        etat.passer('6-1', 'review', 'codex')
        self.assertIn('# Story\n\n**Agent :** codex\n', etat.fiche('6-1').read_text())

    def test_passer_preserve_octets(self):
        contenu = self.status.read_bytes().replace(b'\n', b'\r\n')
        self.status.write_bytes(contenu)
        etat.passer('6-1', 'review')
        self.assertEqual(self.status.read_bytes(), contenu.replace(b'6-1: ready-for-dev', b'6-1: review'))
        with self.assertRaises(ValueError): etat.passer('absent', 'done')

    @patch('etat.subprocess.run')
    def test_prochaine_priorites_pour_et_seuil(self, git):
        self.status.write_text('development_status:\n  6-1: ready-for-dev\n  6-2: in-progress\n  6-3: review\n')
        self.fiche('6-3', 'Agent: Claude')
        git.return_value.stdout = str(int(time.time()))
        self.assertEqual(etat.prochaine(), '6-1')
        # Review chez Claude = PR en attente de Claude : jamais reprise par l'autopilote.
        self.assertEqual(etat.prochaine('tous'), '6-1')
        self.fiche('6-3', 'Agent: codex')
        self.assertEqual(etat.prochaine('tous'), '6-3')
        self.fiche('6-3', 'Agent: codex\n## Reprise\n- Autopilote : échec 1 (x)\n- Autopilote : échec 2 (y)\n')
        self.assertEqual(etat.prochaine('tous'), '6-1')
        self.fiche('6-3', 'Agent: Claude')
        git.return_value.stdout = str(int(time.time()) - 7200)
        self.assertEqual(etat.prochaine(), '6-2')
        git.return_value.stdout = ''
        self.assertEqual(etat.prochaine(), '6-2')
        git.return_value.stdout = str(int(time.time()))
        self.fiche('6-2', 'Agent: relais')
        self.assertEqual(etat.prochaine(), '6-2')
        self.fiche('6-3', 'Agent: codex')
        self.assertEqual(etat.prochaine(), '6-3')

    def test_dependance_non_terminee_attend(self):
        self.status.write_text('development_status:\n  6-1-serveur: ready-for-dev\n  6-2-formulaire: ready-for-dev\n')
        self.fiche('6-1-serveur', 'Agent: claude')
        self.fiche('6-2-formulaire', 'Agent: codex\n**Dépendances :** 6-1-serveur doit être terminée.')
        self.assertEqual(etat.prochaine(), '')
        self.assertEqual(etat.prochaine('tous'), '6-1-serveur')
        etat.passer('6-1-serveur', 'done')
        self.assertEqual(etat.prochaine(), '6-2-formulaire')

    def test_fiche_absente_non_selectionnee(self):
        self.status.write_text('development_status:\n  absente: in-progress\n  6-1: ready-for-dev\n')
        self.assertEqual(etat.prochaine(), '6-1')

    def test_epic(self):
        self.assertEqual(etat.epic(), '')
        etat.passer('6-1', 'done')
        self.assertEqual(etat.epic(), 'epic-6')
        self.status.write_text('development_status:\n  epic-relais: in-progress\n  relais-1: review\n  epic-6-crowdfunding: in-progress\n  6-1: backlog\n')
        self.assertEqual(etat.epic(), 'epic-6-crowdfunding')
        self.status.write_text('development_status:\n  epic-relais: in-progress\n  relais-1: done\n')
        self.assertEqual(etat.epic(), 'epic-relais')

    def test_quota(self):
        self.assertEqual(etat.quota(self.root)['semaine'], '')
        d = self.root / 'sessions/2026/10/01'
        d.mkdir(parents=True)
        p = d / 'rollout-test.jsonl'
        event = {'type': 'event_msg', 'timestamp': '2026-01-01T00:00:00Z', 'payload': {'type': 'token_count', 'rate_limits': {'primary': {'used_percent': 96, 'resets_at': 123}, 'secondary': {'used_percent': 30, 'resets_in_seconds': 60}}}}
        p.write_text(json.dumps(event) + '\nnot-json\n')
        self.assertEqual(etat.quota(self.root), dict(cinq_heures=96, semaine=30, reset_cinq=123, reset_semaine=1767225660))
        event['payload']['rate_limits']['primary']['used_percent'] = 99
        p.write_text(p.read_text() + json.dumps(event) + '\n')
        self.assertEqual(etat.quota(self.root)['cinq_heures'], 99)
        older = d / 'rollout-old.jsonl'
        older.write_text('{}\n')
        os.utime(older, (1, 1))
        self.assertEqual(etat.quota(self.root)['cinq_heures'], 99)

    def test_priorite_et_montee_en_modele(self):
        self.status.write_text('development_status:\n  6-1: ready-for-dev\n  6-2: ready-for-dev\n  6-3: ready-for-dev\n')
        self.fiche('6-1', '**Agent :** codex\n**Priorité :** basse')
        self.fiche('6-2', '**Agent :** codex')
        self.fiche('6-3', '**Agent :** codex\n**Priorité :** haute\n**Niveau :** simple')
        self.assertEqual(etat.prochaine(), '6-3')
        self.assertEqual(etat.meta('6-3')['modele'], 'gpt-5.5')
        self.fiche('6-3', '**Agent :** codex\n**Niveau :** simple\n## Reprise\n- Autopilote : échec 1 (x)\n')
        self.assertEqual(etat.meta('6-3')['modele'], 'gpt-6-astra')
        self.assertEqual(etat.prochaine(), '6-2')
        self.fiche('6-3', '**Agent :** codex\n**Priorité :** basse')
        self.assertEqual(etat.prochaine(), '6-2')

if __name__ == '__main__':
    unittest.main()
