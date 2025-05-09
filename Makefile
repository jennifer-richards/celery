PROJ=celery
PGPIDENT="Celery Security Team"
PYTHON=python
PYTEST=pytest
GIT=git
TOX=tox
ICONV=iconv
FLAKE8=flake8
PYROMA=pyroma
SPHINX2RST=sphinx2rst
RST2HTML=rst2html.py
DEVNULL=/dev/null

TESTDIR=t

SPHINX_DIR=docs/
SPHINX_BUILDDIR="${SPHINX_DIR}/_build"
README=README.rst
README_SRC="docs/templates/readme.txt"
CONTRIBUTING=CONTRIBUTING.rst
CONTRIBUTING_SRC="docs/contributing.rst"
SPHINX_HTMLDIR="${SPHINX_BUILDDIR}/html"
DOCUMENTATION=Documentation

WORKER_GRAPH="docs/images/worker_graph_full.png"

all: help

help:
	@echo "docs                 - Build documentation."
	@echo "test-all             - Run tests for all supported python versions."
	@echo "distcheck ---------- - Check distribution for problems."
	@echo "  test               - Run unittests using current python."
	@echo "  lint ------------  - Check codebase for problems."
	@echo "    apicheck         - Check API reference coverage."
	@echo "    configcheck      - Check configuration reference coverage."
	@echo "    readmecheck      - Check README.rst encoding."
	@echo "    contribcheck     - Check CONTRIBUTING.rst encoding"
	@echo "    flakes --------  - Check code for syntax and style errors."
	@echo "      flakecheck     - Run flake8 on the source code."
	@echo "readme               - Regenerate README.rst file."
	@echo "contrib              - Regenerate CONTRIBUTING.rst file"
	@echo "clean-dist --------- - Clean all distribution build artifacts."
	@echo "  clean-git-force    - Remove all uncommitted files."
	@echo "  clean ------------ - Non-destructive clean"
	@echo "    clean-pyc        - Remove .pyc/__pycache__ files"
	@echo "    clean-docs       - Remove documentation build artifacts."
	@echo "    clean-build      - Remove setup artifacts."
	@echo "bump                 - Bump patch version number."
	@echo "bump-minor           - Bump minor version number."
	@echo "bump-major           - Bump major version number."
	@echo "release              - Make PyPI release."
	@echo ""
	@echo "Docker-specific commands:"
	@echo "  docker-build			- Build celery docker container."
	@echo "  docker-lint        		- Run tox -e lint on docker container."
	@echo "  docker-unit-tests		- Run unit tests on docker container, use '-- -k <TEST NAME>' for specific test run."
	@echo "  docker-bash        		- Get a bash shell inside the container."
	@echo "  docker-docs			- Build documentation with docker."

clean: clean-docs clean-pyc clean-build

clean-dist: clean clean-git-force

bump:
	bumpversion patch

bump-minor:
	bumpversion minor

bump-major:
	bumpversion major

release:
	python setup.py register sdist bdist_wheel upload --sign --identity="$(PGPIDENT)"

Documentation:
	(cd "$(SPHINX_DIR)"; $(MAKE) html)
	mv "$(SPHINX_HTMLDIR)" $(DOCUMENTATION)

docs: clean-docs Documentation

clean-docs:
	-rm -rf "$(SPHINX_BUILDDIR)" "$(DOCUMENTATION)"

lint: flakecheck apicheck configcheck readmecheck

apicheck:
	(cd "$(SPHINX_DIR)"; $(MAKE) apicheck)

configcheck:
	(cd "$(SPHINX_DIR)"; $(MAKE) configcheck)

flakecheck:
	$(FLAKE8) "$(PROJ)" "$(TESTDIR)"

flakediag:
	-$(MAKE) flakecheck

flakes: flakediag

clean-readme:
	-rm -f $(README)

readmecheck-unicode:
	$(ICONV) -f ascii -t ascii $(README) >/dev/null

readmecheck-rst:
	-$(RST2HTML) $(README) >$(DEVNULL)

readmecheck: readmecheck-unicode readmecheck-rst

$(README):
	$(SPHINX2RST) "$(README_SRC)" --ascii > $@

readme: clean-readme $(README) readmecheck

clean-contrib:
	-rm -f "$(CONTRIBUTING)"

$(CONTRIBUTING):
	$(SPHINX2RST) "$(CONTRIBUTING_SRC)" > $@

contrib: clean-contrib $(CONTRIBUTING)

clean-pyc:
	-find . -type f -a \( -name "*.pyc" -o -name "*$$py.class" \) | xargs -r rm
	-find . -type d -name "__pycache__" | xargs -r rm -r

removepyc: clean-pyc

clean-build:
	rm -rf build/ dist/ .eggs/ *.egg-info/ .coverage cover/

clean-git:
	$(GIT) clean -xdn

clean-git-force:
	$(GIT) clean -xdf

test-all: clean-pyc
	$(TOX)

test:
	$(PYTHON) setup.py test

cov:
	$(PYTEST) -x --cov="$(PROJ)" --cov-report=html

build:
	$(PYTHON) setup.py sdist bdist_wheel

distcheck: lint test clean

dist: readme contrib clean-dist build


$(WORKER_GRAPH):
	$(PYTHON) -m celery graph bootsteps | dot -Tpng -o $@

clean-graph:
	-rm -f $(WORKER_GRAPH)

graph: clean-graph $(WORKER_GRAPH)

authorcheck:
	git shortlog -se | cut -f2 | extra/release/attribution.py

.PHONY: docker-build
docker-build:
	@docker compose -f docker/docker-compose.yml build

.PHONY: docker-lint
docker-lint:
	@docker compose -f docker/docker-compose.yml run --rm -w /home/developer/celery celery tox -e lint

.PHONY: docker-unit-tests
docker-unit-tests:
	@docker compose -f docker/docker-compose.yml run --rm -w /home/developer/celery celery tox -e 3.12-unit -- $(filter-out $@,$(MAKECMDGOALS))

# Integration tests are not fully supported when running in a docker container yet so we allow them to
# gracefully fail until fully supported.
# TODO: Add documentation (in help command) when fully supported.
.PHONY: docker-integration-tests
docker-integration-tests:
	@docker compose -f docker/docker-compose.yml run --rm -w /home/developer/celery celery tox -e 3.12-integration-docker -- --maxfail=1000

.PHONY: docker-bash
docker-bash:
	@docker compose -f docker/docker-compose.yml run --rm -w /home/developer/celery celery bash

.PHONY: docker-docs
docker-docs:
	@docker compose -f docker/docker-compose.yml up --build -d docs
	@echo "Waiting 60 seconds for docs service to build the documentation inside the container..."
	@timeout 60 sh -c 'until docker logs $$(docker compose -f docker/docker-compose.yml ps -q docs) 2>&1 | \
		grep "build succeeded"; do sleep 1; done' || \
		(echo "Error! - run manually: docker compose -f ./docker/docker-compose.yml up --build docs"; \
	docker compose -f docker/docker-compose.yml logs --tail=50 docs; false)
	@docker compose -f docker/docker-compose.yml down

.PHONY: catch-all
%: catch-all
	@:
