"""Filter plugins for managing k8s BMH metadata"""

def bmh_nic_names(bmh):
    """Returns the names of the interfaces of a BareMetalHost as a sorted
    list."""
    nics = bmh["status"]["hardware"]["nics"]
    return sorted(set(nic["name"] for nic in nics))


class FilterModule():
    filter_map = {
        'bmh_nic_names': bmh_nic_names,
    }

    def filters(self):
        return self.filter_map
