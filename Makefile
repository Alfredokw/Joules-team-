.PHONY: preflight static-check build baseline asan msan tsan validate validate-detectors schedule smoke run resume audit process clean zip

preflight:
	python3 scripts/preflight.py

static-check:
	python3 scripts/preflight.py --static-only

build:
	python3 scripts/build.py --configuration all

baseline:
	python3 scripts/build.py --configuration baseline

asan:
	python3 scripts/build.py --configuration asan

msan:
	python3 scripts/build.py --configuration msan

tsan:
	python3 scripts/build.py --configuration tsan

validate:
	python3 scripts/validate.py

validate-detectors:
	python3 scripts/validate_detectors.py

schedule:
	python3 scripts/generate_schedule.py

smoke:
	python3 scripts/run_experiment.py --repetitions 1 --no-warmup --configuration baseline --subject bst_oob --workload small --no-cooldown --results-root results/smoke

run:
	python3 scripts/run_experiment.py

resume:
	python3 scripts/run_experiment.py --resume

audit:
	python3 scripts/audit_results.py

process:
	python3 scripts/process_results.py

clean:
	@if [ -d bin ]; then find bin -depth -mindepth 1 -delete; fi
	@if [ -d build ]; then find build -depth -mindepth 1 -delete; fi

zip:
	python3 scripts/package.py
