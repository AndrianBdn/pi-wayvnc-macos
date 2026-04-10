IMAGE   := pi-wayvnc-macos-builder
VERSION := 1.0.0-1

.PHONY: deb image sources clean distclean

# Clone (or update) all upstream sources to the SHAs pinned in
# sources/manifest.txt. Idempotent — safe to re-run.
sources:
	@./scripts/fetch-sources.sh

image:
	docker build -t $(IMAGE) .

deb: sources image
	mkdir -p out
	docker run --rm \
		-v $(CURDIR):/src:ro \
		-v $(CURDIR)/out:/out \
		-e VERSION=$(VERSION) \
		$(IMAGE)
	@echo
	@echo "Built: $$(ls -1 out/*.deb | tail -1)"

clean:
	rm -rf out

distclean: clean
	rm -rf sources/aml sources/neatvnc sources/wayvnc
