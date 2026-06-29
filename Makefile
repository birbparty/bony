.PHONY: test

# Repo-level gate used by /ralph's per-iteration VERIFY step and by the
# registry README's format-gate requirement for any registry/** edit.
# Runs the codegen format check, the Python codegen unit tests, and the
# Nim runtime model compile check.
test:
	python3 codegen/generate.py --check
	python3 -m unittest discover -s codegen -p 'test_*.py'
	nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim
