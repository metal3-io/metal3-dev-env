"""
Filter out managed fields, uids, timestamps and similar from Kubernetes
resources. These fields are often "in the way" when trying to find the relevant
parts or when "restoring" resources to a new cluster.
"""

import copy


def k8s_backup(resources):
    """
    Take a backup of k8s resources by stripping away problematic fields.
    Fields that are automatically created and should normally not be touched
    will be removed so that the resources can safely be restored from this
    "backup".
    Removed fields under .metadata: uid, managedFields, resourceVersion,
    creationTimestamp
    """
    unwanted_metadata_fields = ["uid", "resourceVersion", "creationTimestamp",
                                "managedFields"]

    filtered = copy.deepcopy(resources)
    for resource in filtered:
        for field in unwanted_metadata_fields:
            if "metadata" in resource and field in resource["metadata"]:
                del resource["metadata"][field]

    return filtered


class FilterModule:

    def filters(self):
        return {
            'k8s_backup': k8s_backup
        }
