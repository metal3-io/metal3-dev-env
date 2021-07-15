""" Edit metal3 datatemplate and metaltemplate """
import copy


def edit_template(template, name):
    """common editing for m3dt and m3mt:

    - remove unwanted fields
    - edit template name

    Args:
        template : template object.
        name (str): edited template name.

    Returns:
        edit_template: new template object.

    """

    edited_template = copy.deepcopy(template)

    unwanted_metadata_fields = [
        "managedFields",
        "uid",
        "resourceVersion",
        "ownerReferences",
        "finalizers",
    ]
    for field in unwanted_metadata_fields:
        edited_template["metadata"].pop(field, None)
    edited_template.pop("status", None)

    # Edit name
    edited_template["metadata"]["name"] = name

    return edited_template


def edit_m3dt(resource, name, reference):
    """Filter to edit metal3DataTemplate object"""

    template = edit_template(resource, name)
    template["spec"]["templateReference"] = reference

    return template


def edit_m3mt(resource, name, reference):
    """Filter to edit metal3MetalTemplate object"""

    template = edit_template(resource, name)

    # Edit the reference datatemplate name
    template["spec"]["template"]["spec"]["dataTemplate"]["name"] = reference

    return template


class FilterModule:
    def filters(self):
        return {"edit_m3dt": edit_m3dt, "edit_m3mt": edit_m3mt}
