import unittest
from k8s_fields import k8s_backup


class K8sFieldsTestCase(unittest.TestCase):
    filtered_metadata_keys = ["uid", "resourceVersion", "creationTimestamp",
                              "managedFields"]

    test_secret = {
        "api_version": "v1",
        "kind": "Secret",
        "metadata": {
            "name": "credentials",
            "namespace": "test",
            "uid": "315fbef6-f478-43bf-835b-57d569013062",
            "labels": {
                "test1": "test2"
            },
            "resourceVersion": "54321",
            "creationTimestamp": "2021-06-07T12:35:09Z",
            "managedFields": {
                "one": "two"
            }
        },
        "data": {
            "username": "YWRtaW5AZXhhbXBsZS5jb20K",
            "password": "cGFzc3dvcmQK"
        }
    }
    test_custom_resource = {
        "api_version": "custom.my-api.io/v1",
        "kind": "MyK8sKind",
        "metadata": {
            "name": "my-custom-resource",
            "namespace": "default",
            "uid": "1e475495-0af3-4575-a488-50e9bb02a3de",
            "resourceVersion": "1234",
            "creationTimestamp": "2021-06-07T12:35:09Z",
            "managedFields": {
                "one": "two"
            }
        }
    }
    test_missing_keys = {
        "api_version": "v1",
        "kind": "Deployment",
        "metadata": {
            "name": "test"
        }
    }
    test_missing_metadata = {
        "api_version": "v1",
        "kind": "ConfigMap",
        "data": {
            "variable": "value"
        }
    }

    def test_k8s_backup_deleted_fields(self):
        """Check that unwanted fields are deleted."""
        resources = [self.test_custom_resource, self.test_secret]
        backup = k8s_backup(resources)

        for resource in backup:
            for key in self.filtered_metadata_keys:
                self.assertNotIn(key, resource["metadata"].keys())
            self.assertIn("name", resource["metadata"].keys())

    def test_k8s_backup_preserved_fields(self):
        """Check that fields we care about are not deleted."""
        resources = [self.test_custom_resource, self.test_secret]
        backup = k8s_backup(resources)

        for resource in backup:
            self.assertIn("namespace", resource["metadata"].keys())
            self.assertIn("name", resource["metadata"].keys())

    def test_k8s_backup_preserves_original(self):
        """Check that the filter returns a copy, not a modified original."""
        resources = [self.test_custom_resource, self.test_secret]
        backup = k8s_backup(resources)

        self.assertNotEqual(backup, resources)
        for resource in resources:
            for key in self.filtered_metadata_keys:
                self.assertIn(key, resource["metadata"].keys())

    def test_k8s_backup_missing_keys(self):
        """Check that the filter can handle missing keys."""
        resources = [self.test_missing_keys, self.test_missing_metadata]
        # Just check that we can run this without errors.
        k8s_backup(resources)


if __name__ == "__main__":
    unittest.main()
