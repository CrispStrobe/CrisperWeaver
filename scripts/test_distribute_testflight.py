import unittest

from distribute_testflight import distribute, select_builds


def build(platform, version='0.14.1', number='100', state='VALID'):
    return {
        'data': [{'id': platform, 'attributes': {'version': number, 'processingState': state},
                  'relationships': {'preReleaseVersion': {'data': {'id': 'pre'}}}}],
        'included': [{'id': 'pre', 'attributes': {'version': version, 'platform': platform}}],
    }


class AppleFake:
    def __init__(self, external='READY_FOR_BETA_SUBMISSION'):
        self.groups = []
        self.external = external
        self.writes = []

    def call(self, method, path, data=None, params=None):
        if method == 'GET':
            if path.endswith('/betaBuildLocalizations'):
                return {'data': []}
            if path.endswith('/relationships/betaGroups'):
                return {'data': self.groups}
            if path.endswith('/buildBetaDetail'):
                return {'data': {'id': 'detail', 'attributes': {
                    'internalBuildState': 'IN_BETA_TESTING', 'externalBuildState': self.external}}}
        self.writes.append((method, path, data))
        if path.endswith('/relationships/betaGroups'):
            self.groups.extend(data['data'])
        if path == 'betaAppReviewSubmissions':
            self.external = 'WAITING_FOR_BETA_REVIEW'
        return {}


class DistributionTest(unittest.TestCase):
    def test_build_number_alone_does_not_select_a_different_release(self):
        self.assertEqual(select_builds(build('IOS', version='0.13.0'), '0.14.1', '100'), {})
        self.assertEqual(select_builds(build('IOS', number='99'), '0.14.1', '100'), {})
        self.assertIn('MAC_OS', select_builds(build('MAC_OS'), '0.14.1', '100'))

    def test_failed_processing_and_ambiguous_builds_stop_distribution(self):
        with self.assertRaises(RuntimeError):
            select_builds(build('IOS', state='INVALID'), '0.14.1', '100')
        doc = build('IOS')
        doc['data'] *= 2
        with self.assertRaises(RuntimeError):
            select_builds(doc, '0.14.1', '100')

    def test_group_assignment_and_review_are_idempotent(self):
        api = AppleFake()
        groups = [{'id': 'internal', 'attributes': {'name': 'Internal'}},
                  {'id': 'external', 'attributes': {'name': 'External Testers'}}]
        result = distribute(api, {'id': 'build'}, groups, {'en-US': 'Test microphones'})
        self.assertEqual(result['externalBuildState'], 'WAITING_FOR_BETA_REVIEW')
        self.assertEqual(len(api.groups), 2)
        distribute(api, {'id': 'build'}, groups, {'en-US': 'Test microphones'})
        self.assertEqual(sum(p == 'betaAppReviewSubmissions' for _, p, _ in api.writes), 1)
        self.assertEqual(sum(p.endswith('/relationships/betaGroups') for _, p, _ in api.writes), 1)

    def test_rejected_review_is_not_reported_as_success(self):
        with self.assertRaisesRegex(RuntimeError, 'BETA_REJECTED'):
            distribute(AppleFake('BETA_REJECTED'), {'id': 'build'}, [], {})


if __name__ == '__main__':
    unittest.main()
