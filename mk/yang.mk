BASE := $(shell sed -e '/^\#+RFC_NAME:/!d;s/\#+RFC_NAME: *\(.*\)/\1/' $(ORG))
VERSION := $(shell sed -e '/^\#+RFC_VERSION:/!d;s/\#+RFC_VERSION: *\([0-9]*\)/\1/' $(ORG))
VERSION_NOZERO := $(shell echo "$(VERSION)" | sed -e 's/^0*//')
NEXT_VERSION := $(shell printf "%02d" "$$(($(VERSION_NOZERO) + 1))")
PREV_VERSION := $(shell printf "%02d" "$$(($(VERSION_NOZERO) - 1))")
SBASE := $(patsubst draft-%,%,$(BASE))
#DTYPE := $(word 2,$(subst -, ,$(BASE)))
PBRANCH ?= publish-$(SBASE)-$(VERSION)
PBASE := publish/$(BASE)-$(VERSION)
VBASE := draft/$(BASE)-$(VERSION)
LBASE := draft/$(BASE)-latest
SHELL := /bin/bash
MAIN_BRANCH ?= main #older repos set to master
PUSH_TO_REMOTE ?= origin

# If you have docker you can avoid having to install anything by leaving this.
ifeq ($(CIRCLECI),)
export DOCKRUN ?= docker run --user $(shell id -u) --network=host -v $$(pwd):/work labn/org-rfc
endif
EMACSCMD := $(DOCKRUN) emacs -Q --batch --debug-init --eval '(setq-default indent-tabs-mode nil)' --eval '(setq org-confirm-babel-evaluate nil)' -l ./ox-rfc.el

BRANCH_EXISTS := $(shell git rev-parse --verify $(MAIN_BRANCH) 2>/dev/null)

all: $(LBASE).xml $(LBASE).txt $(LBASE).html # $(LBASE).pdf

clean:
	rm -f $(BASE).xml $(BASE)-*.{txt,html,pdf} $(LBASE).*

git-clean-check:
	@echo Checking for git clean status
	@STATUS="$$(git status -s)"; [[ -z "$$STATUS" ]] || echo "$$STATUS"

push_to_remote:
ifeq ($(strip $(PUSH_TO_REMOTE)),)
		@echo "PUSH_TO_REMOTE is not set. Skipping git push."
else
		git push $(PUSH_TO_REMOTE) $(PBRANCH)
		git push $(PUSH_TO_REMOTE) -f --tags
endif


.PHONY: main-branch-check
main-branch-check:
ifeq ($(BRANCH_EXISTS),)
    $(error Branch '$(MAIN_BRANCH)' does not exist. Exiting.)
endif

.PHONY: publish
publish: main-branch-check git-clean-check $(VBASE).xml $(VBASE).txt $(VBASE).html
	if [ -f $(PBASE).xml ]; then echo "$(PBASE).xml already present, increment version?"; exit 1; fi
	@mkdir -p publish
	cp $(VBASE).xml $(VBASE).txt $(VBASE).html publish
	git checkout -b $(PBRANCH)
	git tag -m "yank.mk: publish-$(SBASE)-$(VERSION)" bp-$(PBRANCH)
	git add $(PBASE).xml $(PBASE).txt $(PBASE).html
	git commit -m "yank.mk: publish-$(SBASE)-$(VERSION)"
	git tag -m "yank.mk: published-$(SBASE)-$(VERSION)" published-$(SBASE)-$(VERSION)
	$(MAKE) PBRANCH=$(PBRANCH) push_to_remote
	git checkout $(MAIN_BRANCH)
	git merge --ff-only $(PBRANCH)
	sed -i -e 's/\#+RFC_VERSION: *\([0-9]*\)/\#+RFC_VERSION: $(NEXT_VERSION)/' $(ORG)
	git commit -am "yank.mk: new version -$(NEXT_VERSION) post-publish $(SBASE)-$(VERSION)"
	$(MAKE) PBRANCH=$(MAIN_BRANCH) push_to_remote

#republish:
#	sed -i -e 's/\#+RFC_VERSION: *\([0-9]*\)/\#+RFC_VERSION: $(PREV_VERSION)/' $(ORG)
#	cp $(VBASE).xml $(VBASE).txt $(VBASE).html publish
#	git add $(PBASE).xml $(PBASE).txt $(PBASE).html
#	git commit -m "publish-$(SBASE)-$(VERSION)-update"
#	git tag -a -f -m "yank.mk publish-$(SBASE)-$(VERSION) update" publish-$(SBASE)-$(VERSION)
#	sed -i -e 's/\#+RFC_VERSION: *\([0-9]*\)/\#+RFC_VERSION: $(VERSION)/' $(ORG)

draft:
	mkdir -p draft

$(VBASE).xml: $(ORG) ox-rfc.el test
	mkdir -p draft
	$(EMACSCMD) $< -f ox-rfc-export-to-xml
	mv $(BASE).xml $@

%-$(VERSION).txt: %-$(VERSION).xml
	$(DOCKRUN) xml2rfc --cache /tmp --text $< > $@

%-$(VERSION).html: %-$(VERSION).xml
	$(DOCKRUN) xml2rfc --cache /tmp --html $< > $@

%-$(VERSION).pdf: %-$(VERSION).xml
	$(DOCKRUN) xml2rfc --cache /tmp --pdf $< > $@

$(LBASE).%: $(VBASE).%
	cp $< $@

# ------------
# Verification
# ------------

idnits: $(VBASE).txt
	if [ ! -e idnits ]; then curl -fLO 'http://tools.ietf.org/tools/idnits/idnits'; chmod 755 idnits; fi
	./idnits --verbose $<

# -----
# Tools
# -----

ox-rfc.el:
	curl -fLO 'https://raw.githubusercontent.com/choppsv1/org-rfc-export/master/ox-rfc.el'

run-test: $(ORG) ox-rfc.el
	$(EMACSCMD) $< -f ox-rfc-run-test-blocks 2>&1

test: $(ORG) ox-rfc.el
	@echo Testing $<
	@result="$$($(EMACSCMD) $< -f ox-rfc-run-test-blocks 2>&1)"; \
	if [ -n "$$(echo \"$$result\"|grep FAIL)" ]; then \
		grep RESULT <<< "$$result" || true; \
		exit 1; \
	else \
		grep RESULT <<< "$$result" || true; \
	fi;
