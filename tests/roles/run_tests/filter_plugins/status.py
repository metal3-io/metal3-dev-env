""" filtering k8s_info resources """

from ansible.utils.display import Display

display = Display()


def msg(key, resources):
    return "could not find %r key in %r" % (key, resources)


def filter_phase(resources, phase):
    """Filter resources based on a defined phase

    Args:
        resources : Json object contains a list of k8s resources.
        phase (str): The status phase of the filtered resources
                    e.g. 'running', 'provisioning', 'deleting'.

    Returns:
        list: A list of resources in the defined phase.
    """

    filtered = []
    for r in resources:
        try:
            if r["status"]["phase"].lower() == phase:
                filtered.append(r)
        except KeyError:
            display.warning(msg("['status']['phase']", r))

    return filtered


def filter_ready(resources):
    """return resources based on defined ready status"""
    filtered = []
    for r in resources:
        try:
            if r["status"]["ready"]:
                filtered.append(r)
        except KeyError:
            display.warning(msg("['status']['ready']", r))

    return filtered


def filter_provisioning(resources, state):
    """Filter resources based on a defined provisioning state

    Args:
        resources : Json object contains a list of k8s resources.
        state (str): Comma-delimited list of provisioning states of the
                    filtered resources e.g. 'provisioned',
                    'available,ready', 'deprovisioning'

    Returns:
        list: A list of resources in the defined provisioning state.
    """
    states = set(state.split(','))
    filtered = []
    for r in resources:
        try:
            if r["status"]["provisioning"]["state"].lower() in states:
                filtered.append(r)
        except KeyError:
            display.warning(msg("['status']['provisioning']['state']", r))

    return filtered

def filter_unavailable_replicas(resources):
    """Filter deployments with unavailable replicas

    Args:
        resources : Json object contains a list of deployments.

    Returns:
        list: A list of deployments with unavailable replicas.
    """
 
    filtered = []
    for r in resources:
        try:
            if r["status"]["unavailableReplicas"] > 0:
                filtered.append(r)
        except KeyError:
            pass

    return filtered

class FilterModule:
    def filters(self):
        filters = {
            "filter_phase": filter_phase,
            "filter_ready": filter_ready,
            "filter_provisioning": filter_provisioning,
            "filter_unavailable_replicas": filter_unavailable_replicas,
        }
        return filters
