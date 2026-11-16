import json
import unittest

from cd_request import platform_reference, prepare_request


class PlatformReferenceTests(unittest.TestCase):
    def setUp(self):
        self.image = 'ghcr.io/example/foundation@sha256:' + 'a' * 64
        self.index = {'manifests': [
            {'digest': 'sha256:' + 'b' * 64, 'platform': {'os': 'linux', 'architecture': 'amd64'}},
            {'digest': 'sha256:' + 'c' * 64, 'platform': {'os': 'linux', 'architecture': 'arm64', 'variant': 'v8'}},
            {'digest': 'sha256:' + 'd' * 64, 'platform': {'os': 'unknown', 'architecture': 'unknown'}},
        ]}

    def test_platform_pulls_use_distinct_children_of_the_pinned_index(self):
        amd64 = platform_reference(self.image, self.index, 'amd64')
        arm64 = platform_reference(self.image, self.index, 'arm64')
        self.assertEqual(amd64, 'ghcr.io/example/foundation@sha256:' + 'b' * 64)
        self.assertEqual(arm64, 'ghcr.io/example/foundation@sha256:' + 'c' * 64)
        self.assertNotEqual(amd64, arm64)

    def test_missing_or_ambiguous_platform_is_rejected(self):
        with self.assertRaises(ValueError):
            platform_reference(self.image, self.index, 'ppc64le')
        self.index['manifests'].append(self.index['manifests'][0])
        with self.assertRaises(ValueError):
            platform_reference(self.image, self.index, 'amd64')

    def test_invalid_platform_digest_is_rejected(self):
        self.index['manifests'][0]['digest'] = 'not-a-digest'
        with self.assertRaises(ValueError):
            platform_reference(self.image, self.index, 'amd64')


class RequestTests(unittest.TestCase):
    def setUp(self):
        self.values = {
            'GITHUB_REPOSITORY': 'islandawolfe-02/Basic-GitOps-using-Argo-CD-and-Minikube',
            'GITHUB_SHA': 'a' * 40,
            'BUILD_IMAGE': 'true',
            'DEPLOY': 'true',
            'EXISTING_IMAGE': '',
            'DEPLOY_NAMESPACE': 'my-deployment',
            'DEPLOYMENT_NAME': 'foundation-cd',
            'APP_PORT': '18090',
            'GRAFANA_PORT': '3001',
            'LOKI_PORT': '3101',
            'LAB_ENV': 'workshop-green',
            'CD_DISPATCH_TOKEN': 'test-secret-not-a-real-token',
        }

    def test_build_and_deploy_keeps_the_selected_destination_without_the_secret(self):
        image_name, request = prepare_request(self.values)
        self.assertEqual(image_name, 'ghcr.io/' + self.values['GITHUB_REPOSITORY'].lower())
        self.assertEqual(request['inputs']['namespace'], 'my-deployment')
        self.assertEqual(request['inputs']['image'], '')
        self.assertNotIn(self.values['CD_DISPATCH_TOKEN'], json.dumps(request))

    def test_build_only_needs_no_deployment_settings_or_secret(self):
        self.values.update(DEPLOY='false', DEPLOY_NAMESPACE='', CD_DISPATCH_TOKEN='')
        prepare_request(self.values)

    def test_deploy_without_build_requires_this_packages_digest(self):
        self.values['BUILD_IMAGE'] = 'false'
        image_name, _ = prepare_request({**self.values, 'BUILD_IMAGE': 'true'})
        for image in ('', image_name + ':latest', 'ghcr.io/someone/other@sha256:' + 'b' * 64):
            with self.subTest(image=image), self.assertRaises(ValueError):
                prepare_request({**self.values, 'EXISTING_IMAGE': image})
        image = image_name + '@sha256:' + 'b' * 64
        _, request = prepare_request({**self.values, 'EXISTING_IMAGE': image})
        self.assertEqual(request['inputs']['image'], image)

    def test_protected_or_invalid_namespaces_are_rejected(self):
        for namespace in ('', 'argocd', 'observability', 'p1-islandawolfe-02', 'default',
                          'kube-system', 'kube-public', 'Uppercase', '../other', 'a\nimage=x', 'a' * 64):
            with self.subTest(namespace=namespace), self.assertRaises(ValueError):
                prepare_request({**self.values, 'DEPLOY_NAMESPACE': namespace})

    def test_invalid_or_conflicting_ports_are_rejected(self):
        for port in ('3001', '18080', '18081', '18082', '3000', '3100', '1023',
                     '65536', '018090', '18090\nimage=x', '$(false)'):
            with self.subTest(port=port), self.assertRaises(ValueError):
                prepare_request({**self.values, 'APP_PORT': port})

    def test_port_boundaries_are_accepted(self):
        prepare_request({**self.values, 'APP_PORT': '1024', 'LOKI_PORT': '65535'})

    def test_invalid_identity_environment_name_or_boolean_is_rejected(self):
        for key, value in (('GITHUB_REPOSITORY', 'bad\nrepository'), ('GITHUB_SHA', 'not-a-sha'),
                           ('LAB_ENV', 'production'), ('DEPLOYMENT_NAME', '../other'),
                           ('BUILD_IMAGE', 'yes'), ('DEPLOY', 'yes')):
            with self.subTest(key=key), self.assertRaises(ValueError):
                prepare_request({**self.values, key: value})

    def test_deployment_requires_the_trigger_secret(self):
        with self.assertRaisesRegex(ValueError, 'CD_DISPATCH_TOKEN'):
            prepare_request({**self.values, 'CD_DISPATCH_TOKEN': ''})


if __name__ == '__main__':
    unittest.main()
