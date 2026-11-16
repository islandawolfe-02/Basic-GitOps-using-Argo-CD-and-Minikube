"""Validate the optional foundation CD request before publishing or dispatching."""

import json
import os
import re
from pathlib import Path


def platform_reference(image, index, architecture):
    """Select a child manifest so Docker stores each architecture separately."""
    matches = [
        manifest.get('digest', '')
        for manifest in index.get('manifests', [])
        if manifest.get('platform', {}).get('os') == 'linux'
        and manifest.get('platform', {}).get('architecture') == architecture
    ]
    if len(matches) != 1:
        raise ValueError(f'Expected one linux/{architecture} image manifest, found {len(matches)}')
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', matches[0]):
        raise ValueError(f'Invalid linux/{architecture} image digest')
    return image.split('@', 1)[0] + '@' + matches[0]


def prepare_request(values):
    repository = values['GITHUB_REPOSITORY']
    revision = values['GITHUB_SHA']
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Invalid source repository')
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('Invalid source commit')
    if values['BUILD_IMAGE'] not in ('true', 'false') or values['DEPLOY'] not in ('true', 'false'):
        raise ValueError('Build and deploy must be boolean selections')
    if values['LAB_ENV'] not in ('workshop-blue', 'workshop-green'):
        raise ValueError('runtime.env must select workshop-blue or workshop-green')

    image_name = 'ghcr.io/' + repository.lower()
    image = '' if values['BUILD_IMAGE'] == 'true' else values['EXISTING_IMAGE']
    if values['BUILD_IMAGE'] == 'false' and values['DEPLOY'] == 'true':
        if not re.fullmatch(re.escape(image_name) + r'@sha256:[0-9a-f]{64}', image):
            raise ValueError('Supply this app package as ghcr.io/owner/repo@sha256:<64 hex characters>')

    if values['DEPLOY'] == 'true':
        if not values.get('CD_DISPATCH_TOKEN'):
            raise ValueError('Add the CD_DISPATCH_TOKEN repository secret before requesting deployment')
        for key in ('DEPLOY_NAMESPACE', 'DEPLOYMENT_NAME'):
            if not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', values[key]):
                raise ValueError(f'{key} must be a lowercase Kubernetes name of 1–63 characters')
        namespace = values['DEPLOY_NAMESPACE']
        if namespace in ('default', 'argocd', 'observability', 'p1-islandawolfe-02') or namespace.startswith('kube-'):
            raise ValueError('Choose a namespace separate from the original deployment and cluster services')
        ports = [values[key] for key in ('APP_PORT', 'GRAFANA_PORT', 'LOKI_PORT')]
        if any(not re.fullmatch(r'[1-9][0-9]{3,4}', port) or not 1024 <= int(port) <= 65535 for port in ports):
            raise ValueError('Local ports must be whole numbers between 1024 and 65535')
        if len(set(ports)) != 3:
            raise ValueError('App, Grafana and Loki local ports must differ')
        if set(ports) & {'18080', '18081', '18082', '3000', '3100'}:
            raise ValueError('Selected ports overlap the original project or reproduction ports')

    request = {
        'ref': 'main',
        'inputs': {
            'project': 'foundation',
            'source_repository': repository,
            'source_revision': revision,
            'image': image,
            'namespace': values['DEPLOY_NAMESPACE'],
            'deployment_name': values['DEPLOYMENT_NAME'],
            'app_port': values['APP_PORT'],
            'grafana_port': values['GRAFANA_PORT'],
            'loki_port': values['LOKI_PORT'],
            'lab_env': values['LAB_ENV'],
        },
    }
    return image_name, request


if __name__ == '__main__':
    try:
        image_name, request = prepare_request(os.environ)
    except (ValueError, KeyError) as error:
        raise SystemExit(str(error))
    Path('deployment-request.json').write_text(json.dumps(request, indent=2) + '\n')
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'image_name={image_name}\nlab_env={request["inputs"]["lab_env"]}\n')
