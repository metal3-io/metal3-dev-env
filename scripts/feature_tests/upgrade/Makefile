M3PATH := "$(dirname "$(readlink -f "${0}")")../../../"

all: fetch_manifests upgrade
fetch_manifests:
	./../../fetch_manifests.sh
upgrade:
	./upgrade.sh
