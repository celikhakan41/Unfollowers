# Unfollowers iOS - Robust Makefile (Codex-friendly)
# - Predictable: make / make build / make test / make run
# - Clear failures: set -o pipefail + xcbeautify
# - Simulator: boot + bootstatus + simctl install/launch (booted)
# - App path: derived data build settings'lerinden otomatik çıkarır

SHELL := /bin/bash
.SHELLFLAGS := -lc

# ===== Değişkenler =====
SCHEME        := Unfollowers
CONFIGURATION := Debug
SIMULATOR     := iPhone 16 Pro
BUNDLE_ID     := com.hakancelik.Unfollowers

# Logs configuration (overridable)
LOGS_DIR      ?= .logs
LOGS_KEEP     ?= 20

DERIVED_DATA  := .build
SIM_UDID      := DE53E21B-B26F-41A3-9C29-795F613D663D
DESTINATION   := platform=iOS Simulator,id=$(SIM_UDID)
# Workspace varsa onu kullan, yoksa xcodeproj
WORKSPACE := $(firstword $(wildcard *.xcworkspace))
PROJECT   := $(firstword $(wildcard *.xcodeproj))

# xcodebuild için baz argümanlar
ifeq ($(strip $(WORKSPACE)),)
  XCB_ARGS := -project "$(PROJECT)"
else
  XCB_ARGS := -workspace "$(WORKSPACE)"
endif

# ===== Yardımcı hedefler =====
.PHONY: help list-sims boot-sim clean build test run install launch app-path prune-logs

help:
	@echo "📖 Unfollowers Makefile Komutları:"
	@echo ""
	@echo "  make            - Derle + kur + çalıştır (varsayılan)"
	@echo "  make build      - Sadece derle"
	@echo "  make test       - Unit testleri çalıştır"
	@echo "  make run        - Derle + kur + çalıştır"
	@echo "  make clean      - DerivedData temizle"
	@echo "  make list-sims  - Simülatör cihaz listesini göster"
	@echo ""

list-sims:
	@xcrun simctl list devices available

boot-sim:
	@echo "📱 Simülatör hazırlanıyor: $(SIMULATOR)"
	@open -a Simulator
	@xcrun simctl boot "$(SIM_UDID)" 2>/dev/null || true
	@xcrun simctl bootstatus "$(SIM_UDID)" -b

clean:
	@echo "🧹 Temizleniyor..."
	@rm -rf "$(DERIVED_DATA)"
	@xcodebuild $(XCB_ARGS) -scheme "$(SCHEME)" clean >/dev/null 2>&1 || true
	@echo "✅ Temizlik tamam"

# ===== Build =====
build:
	@echo "📦 Build: $(SCHEME) ($(CONFIGURATION))"
	@set -o pipefail && \
	xcodebuild $(XCB_ARGS) \
	  -scheme "$(SCHEME)" \
	  -configuration "$(CONFIGURATION)" \
	  -destination 'generic/platform=iOS Simulator' \
	  -derivedDataPath "$(DERIVED_DATA)" \
	  build | xcbeautify
	@$(MAKE) -s prune-logs

# ===== Test =====
test: boot-sim
	@echo "🧪 Test: $(SCHEME) ($(CONFIGURATION))"
	@set -o pipefail && \
	xcodebuild $(XCB_ARGS) \
	  -scheme "$(SCHEME)" \
	  -configuration "$(CONFIGURATION)" \
	  -parallel-testing-enabled NO \
	  -destination '$(DESTINATION)' \
	  -derivedDataPath "$(DERIVED_DATA)" \
	  test | xcbeautify
	@$(MAKE) -s prune-logs

# ===== .app yolunu bul =====
# Not: build settings'ten TARGET_BUILD_DIR + WRAPPER_NAME okuyup .app path üretir
app-path:
	@set -o pipefail && \
	TARGET_BUILD_DIR=$$(xcodebuild $(XCB_ARGS) -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -destination '$(DESTINATION)' -derivedDataPath "$(DERIVED_DATA)" -showBuildSettings 2>/dev/null | awk -F' = ' '/TARGET_BUILD_DIR/{print $$2; exit}'); \
	WRAPPER_NAME=$$(xcodebuild $(XCB_ARGS) -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -destination '$(DESTINATION)' -derivedDataPath "$(DERIVED_DATA)" -showBuildSettings 2>/dev/null | awk -F' = ' '/WRAPPER_NAME/{print $$2; exit}'); \
	APP_PATH="$$TARGET_BUILD_DIR/$$WRAPPER_NAME"; \
	if [ -z "$$TARGET_BUILD_DIR" ] || [ -z "$$WRAPPER_NAME" ] || [ ! -d "$$APP_PATH" ]; then \
	  echo "❌ .app yolu bulunamadı. (TARGET_BUILD_DIR/WRAPPER_NAME)"; \
	  echo "   İpucu: Önce 'make build' çalıştır ve scheme/destination doğru mu kontrol et."; \
	  exit 1; \
	fi; \
	echo "$$APP_PATH"

# ===== Install + Launch =====
install: build boot-sim
	@echo "📥 Simülatöre kurulum..."
	@APP_PATH="$$(make -s app-path)"; \
	echo "   APP: $$APP_PATH"; \
	xcrun simctl install booted "$$APP_PATH"

launch: boot-sim
	@echo "🚀 Uygulama açılıyor: $(BUNDLE_ID)"
	@xcrun simctl launch booted "$(BUNDLE_ID)" || (echo "❌ Launch failed. Bundle ID doğru mu?"; exit 1)

run: install launch
	@echo "✅ Run tamam"
	@$(MAKE) -s prune-logs

# Varsayılan: make => run
.DEFAULT_GOAL := run

# ===== Logs Prune =====
prune-logs:
	@mkdir -p "$(LOGS_DIR)"
	@to_delete="$$(ls -1t "$(LOGS_DIR)"/*.log 2>/dev/null | awk 'NR>$(LOGS_KEEP)' || true)"; \
	if [ -n "$$to_delete" ]; then \
	  echo "🧹 Pruning old logs:"; \
	  echo "$$to_delete"; \
	  echo "$$to_delete" | xargs -n 1 rm -f; \
	fi
