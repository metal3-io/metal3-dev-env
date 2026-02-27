# -*- mode: Python -*-
# External Tilt extensions we depend on
load('ext://git_resource', 'git_resource', 'git_checkout')
load('ext://color', 'color')
load('ext://cert_manager', 'deploy_cert_manager')

# Custom flag for tilt down
config.define_bool("prune")
cfg = config.parse()

allow_k8s_contexts('kubernetes-admin@kubernetes')
# Anonymous, ephemeral image registry
default_registry('ttl.sh')

# ==============================================================================
# Vars
# ==============================================================================
# versions
CAPI_VERSION = os.getenv('CAPI_VERSION', 'v1.11.3')
CERT_MANAGER_VERSION = os.getenv('CERT_MANAGER_VERSION', 'v1.19.1')

# capi core providers
CAPI_BOOTSTRAP_PROVIDER = os.getenv('CAPI_BOOTSTRAP_PROVIDER', 'kubeadm')
CAPI_CONTROLPLANE_PROVIDER = os.getenv('CAPI_CONTROLPLANE_PROVIDER', 'kubeadm')
CAPI_CORE_PROVIDER = os.getenv('CAPI_CORE_PROVIDER', 'cluster-api')

capi_components_url = 'https://github.com/kubernetes-sigs/cluster-api/releases/download/{}/cluster-api-components.yaml'.format(CAPI_VERSION)
local_dev_dir = os.getenv('LOCAL_DEV_DIR', './local-dev')

bmo = 'baremetal-operator'
capm3 = 'cluster-api-provider-metal3'
ipam = 'ip-address-manager'
irso = 'ironic-standalone-operator'
bmo_kustomize_dir = '{}/{}/config/'.format(local_dev_dir, bmo)
capm3_kustomize_dir = '{}/{}/config/default'.format(local_dev_dir, capm3)
ipam_kustomize_dir = '{}/{}/config/default'.format(local_dev_dir, ipam)
irso_kustomize_dir = '{}/{}/config/default'.format(local_dev_dir, irso)

# ==============================================================================
# Helper Functions
# ==============================================================================
def check_tools(tools):
    for name in tools:
        if str(local("%s version 2>/dev/null || true" % name, quiet=True, echo_off=True)) == "":
            fail("%s not found in PATH" % name)
        print_success("%s OK" % name)

def check_envsubst():
    # Verify envsubst is the a8m version (https://github.com/a8m/envsubst)
    # and not the limited gettext version shipped with Linux.
    help_out = str(local("envsubst -help 2>&1 || true", quiet=True, echo_off=True)).strip()
    if "no-unset" not in help_out:
        fail(
         "\n\n" +
         "  Wrong envsubst detected (GNU gettext)\n\n" +
         "  The a8m/envsubst binary is required:\n" +
         "  https://github.com/a8m/envsubst/releases\n"
        )
    print_success("envsubst OK (a8m)")

def cleanup_repos():
    print('Cleaning up {}...'.format(local_dev_dir))
    local('rm -rf {}'.format(local_dev_dir), quiet=True, echo_off=True)
    print_success('Local clones cleanup complete!')

def cleanup_kustomize(name, kustomize_dir, use_envsubst=False):
    print('Cleaning up {} resources...'.format(name))
    cmd = 'kustomize build ' + kustomize_dir
    if use_envsubst:
        cmd += ' | envsubst'
    cmd += ' | kubectl delete --ignore-not-found=true -f -'
    local(cmd, quiet=True, echo_off=True)
    print_success('{} cleanup complete!'.format(name))
    
def print_success(message):
    print('\033[32m ✓\033[0m ' + message)

def get_git_remote(env_var, default_org, default_repo):
    
    # Constructs a git remote URL from various input formats.
    # Accepts:
    # - Full URL: https://github.com/org/repo.git
    # - org/repo format
    # - Just repo name (uses default_org)

    value = os.getenv(env_var, '')
    if not value:
        return 'https://github.com/{}/{}.git'.format(default_org, default_repo)
    
    if value.startswith('http://') or value.startswith('https://'):
        return value if value.endswith('.git') else '{}.git'.format(value)
    
    if '/' in value:
        org, repo = value.split('/', 1)
        repo = repo.replace('.git', '')
        return 'https://github.com/{}/{}.git'.format(org, repo)
    
    repo = value.replace('.git', '')
    return 'https://github.com/{}/{}.git'.format(default_org, repo)

# ==============================================================================
# Repository Configuration
# ==============================================================================
repos = {
    'capm3': {
        'remote': get_git_remote('CAPM3_REMOTE', 'metal3-io', capm3),
        'branch': os.getenv('CAPM3_BRANCH', 'main'),
        'dir': capm3,
        'display_name': 'CAPM3',
        'kustomize_subpath': 'config/default',
        'needs_envsubst': True
    },
    'bmo': {
        'remote': get_git_remote('BMO_REMOTE', 'metal3-io', bmo),
        'branch': os.getenv('BMO_BRANCH', 'main'),
        'dir': bmo,
        'display_name': 'BMO',
        'kustomize_subpath': 'config/',
        'needs_envsubst': False
    },
    'ipam': {
        'remote': get_git_remote('IPAM_REMOTE', 'metal3-io', 'metal3-ipam'),
        'branch': os.getenv('IPAM_BRANCH', 'main'),
        'dir': ipam,
        'display_name': 'IPAM',
        'kustomize_subpath': 'config/default',
        'needs_envsubst': True
    },
    'irso': {
        'remote': get_git_remote('IRSO_REMOTE', 'metal3-io', irso),
        'branch': os.getenv('IRSO_BRANCH', 'main'),
        'dir': irso,
        'display_name': 'IRSO',
        'kustomize_subpath': 'config/default',
        'needs_envsubst': False
    }
}

# ==============================================================================
# What happens when 'tilt up' is run
# ==============================================================================
if config.tilt_subcommand == 'up':
    # Clone repositories if they don't exist
    for key, repo in repos.items():
        repo_path = os.path.join(local_dev_dir, repo['dir'])
        if not os.path.exists(repo_path):
            print('🐙 Git cloning {} into {}'.format(repo['display_name'], repo_path))
            git_checkout('{}#{}'.format(repo['remote'], repo['branch']), checkout_dir=repo_path)
            if not os.path.exists(repo_path):
                print(color.red('ERROR: ') + 'Failed to clone the {} repo into {}'.format(repo['display_name'], repo_path))

    check_tools(["docker", "kubectl", "clusterctl", "kustomize"])
    check_envsubst()
    deploy_cert_manager(version=CERT_MANAGER_VERSION)
    
    # Initialize CAPI
    clusterctl_cmd = 'clusterctl init --bootstrap {}:{} --control-plane {}:{} --core {}:{}'.format(
        CAPI_BOOTSTRAP_PROVIDER, CAPI_VERSION,
        CAPI_CONTROLPLANE_PROVIDER, CAPI_VERSION,
        CAPI_CORE_PROVIDER, CAPI_VERSION
    )
    local_resource('capi', cmd=clusterctl_cmd, labels=['capi'])

    # Build and apply kustomize manifests
    for key, repo in repos.items():
        kustomize_dir = '{}/{}/{}'.format(local_dev_dir, repo['dir'], repo['kustomize_subpath'])
        cmd = 'kustomize build ' + kustomize_dir
        if repo['needs_envsubst']:
            cmd += ' | envsubst'
        content = local(cmd, quiet=True)
        k8s_yaml(content)

    # Build Docker images
    for key, repo in repos.items():
        docker_build(
            'quay.io/metal3-io/{}'.format(repo['dir']),
            '{}/{}/'.format(local_dev_dir, repo['dir']),
            dockerfile='{}/{}/Dockerfile'.format(local_dev_dir, repo['dir'])
        )

    # Configure k8s resources for CAPM3
    k8s_resource(
        'capm3-controller-manager',
        objects=[
            'capm3-system:namespace',
            'metal3clusters.infrastructure.cluster.x-k8s.io:customresourcedefinition',
            'metal3clustertemplates.infrastructure.cluster.x-k8s.io:customresourcedefinition',
            'metal3dataclaims.infrastructure.cluster.x-k8s.io:customresourcedefinition',
            'metal3datas.infrastructure.cluster.x-k8s.io:customresourcedefinition',
            'metal3datatemplates.infrastructure.cluster.x-k8s.io:customresourcedefinition',
            'metal3machines.infrastructure.cluster.x-k8s.io:customresourcedefinition',
            'metal3machinetemplates.infrastructure.cluster.x-k8s.io:customresourcedefinition',
            'metal3remediations.infrastructure.cluster.x-k8s.io:customresourcedefinition',
            'metal3remediationtemplates.infrastructure.cluster.x-k8s.io:customresourcedefinition',
            'capm3-mutating-webhook-configuration:mutatingwebhookconfiguration',
            'capm3-manager:serviceaccount',
            'capm3-leader-election-role:role',
            'capm3-manager-role:clusterrole',
            'capm3-leader-election-rolebinding:rolebinding',
            'capm3-manager-rolebinding:clusterrolebinding',
            'capm3-capm3fasttrack-configmap:configmap',
            'capm3-serving-cert:certificate',
            'capm3-selfsigned-issuer:issuer',
            'capm3-validating-webhook-configuration:validatingwebhookconfiguration'
        ],
        new_name='capm3',
        labels=['metal3'],
        resource_deps=['ipam'],
        pod_readiness='wait'
    )
    
    # Configure k8s resources for BMO
    k8s_resource(
        'baremetal-operator-controller-manager',
        objects=[
            'baremetal-operator-system:namespace',
            'baremetalhosts.metal3.io:customresourcedefinition',
            'bmceventsubscriptions.metal3.io:customresourcedefinition',
            'dataimages.metal3.io:customresourcedefinition',
            'firmwareschemas.metal3.io:customresourcedefinition',
            'hardwaredata.metal3.io:customresourcedefinition',
            'hostfirmwarecomponents.metal3.io:customresourcedefinition',
            'hostfirmwaresettings.metal3.io:customresourcedefinition',
            'hostupdatepolicies.metal3.io:customresourcedefinition',
            'hostclaims.metal3.io:customresourcedefinition',
            'hostdeploypolicies.metal3.io:customresourcedefinition',
            'preprovisioningimages.metal3.io:customresourcedefinition',
            'baremetal-operator-controller-manager:serviceaccount',
            'baremetal-operator-leader-election-role:role',
            'baremetal-operator-manager-role:clusterrole',
            'baremetal-operator-metrics-auth-role:clusterrole',
            'baremetal-operator-metrics-reader:clusterrole',
            'baremetal-operator-leader-election-rolebinding:rolebinding',
            'baremetal-operator-manager-rolebinding:clusterrolebinding',
            'baremetal-operator-metrics-auth-rolebinding:clusterrolebinding',
            'ironic:configmap',
            'baremetal-operator-serving-cert:certificate',
            'baremetal-operator-selfsigned-issuer:issuer',
            'baremetal-operator-validating-webhook-configuration:validatingwebhookconfiguration'
        ],
        new_name='bmo',
        labels=['metal3'],
        resource_deps=['ironic'],
        pod_readiness='wait'
    )

    # Configure k8s resources for IPAM
    k8s_resource(
        'ipam-controller-manager',
        objects=[
            'metal3-ipam-system:namespace',
            'ipaddresses.ipam.metal3.io:customresourcedefinition',
            'ipclaims.ipam.metal3.io:customresourcedefinition',
            'ippools.ipam.metal3.io:customresourcedefinition',
            'ipam-mutating-webhook-configuration:mutatingwebhookconfiguration',
            'ipam-manager:serviceaccount',
            'ipam-leader-election-role:role',
            'ipam-manager-role:clusterrole',
            'ipam-leader-election-rolebinding:rolebinding',
            'ipam-manager-rolebinding:clusterrolebinding',
            'ipam-serving-cert:certificate',
            'ipam-selfsigned-issuer:issuer',
            'ipam-validating-webhook-configuration:validatingwebhookconfiguration'
        ],
        new_name='ipam',
        labels=['metal3'],
        resource_deps=['bmo'],
        pod_readiness='wait'
    )

    k8s_resource(
        'ironic-standalone-operator-controller-manager',
        objects=[
            'ironic-standalone-operator-system:namespace',
            'ironics.ironic.metal3.io:customresourcedefinition',
            'ironic-standalone-operator-controller-manager:serviceaccount',
            'ironic-standalone-operator-leader-election-role:role',
            'ironic-standalone-operator-manager-role:clusterrole',
            'ironic-standalone-operator-leader-election-rolebinding:rolebinding',
            'ironic-standalone-operator-manager-rolebinding:clusterrolebinding',
            'ironic-standalone-operator-ironic-standalone-operator-config:configmap',
            'ironic-standalone-operator-serving-cert:certificate',
            'ironic-standalone-operator-selfsigned-issuer:issuer',
            'ironic-standalone-operator-validating-webhook-configuration:validatingwebhookconfiguration'
        ],
        new_name='ironic',
        labels=['metal3'],
        pod_readiness='wait'
    )

# ==============================================================================
# What happens when 'tilt down' is run
# ==============================================================================
if config.tilt_subcommand == 'down':
    print('Cleaning up CAPI resources...')
    local('curl -sSL {} | envsubst | kubectl delete --force --ignore-not-found=true -f -'.format(capi_components_url), quiet=True, echo_off=True)
    print_success('CAPI cleanup complete!')

    # Clean up in reverse dependency order
    cleanup_kustomize('CAPM3', capm3_kustomize_dir, use_envsubst=True)
    cleanup_kustomize('IPAM', ipam_kustomize_dir, use_envsubst=True)
    cleanup_kustomize('BMO', bmo_kustomize_dir, use_envsubst=False) 
    cleanup_kustomize('Ironic', irso_kustomize_dir, use_envsubst=False)

    print('Cleaning up cert-manager...')
    local('kubectl delete namespace cert-manager --force --ignore-not-found=true', quiet=True, echo_off=True)
    print_success('cert-manager cleanup complete!')
    
    print('Cleaning up Docker resources...')
    local('tilt docker-prune', quiet=True, echo_off=True)
    print_success('Docker resources cleanup complete!')

    if cfg.get('prune', False):
        cleanup_repos()
