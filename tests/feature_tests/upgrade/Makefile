M3PATH := "$(dirname "$(readlink -f "${0}")")../../../"

all: fetch_manifests upgrade
fetch_manifests:
	./../../scripts/fetch_manifests.sh
upgrade:
	./upgrade.sh
