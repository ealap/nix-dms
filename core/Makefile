BINARY_NAME=dms
BINARY_NAME_INSTALL=dankinstall
SOURCE_DIR=cmd/dms
SOURCE_DIR_INSTALL=cmd/dankinstall
BUILD_DIR=bin
SHELL_SRC=../quickshell
EMBED_DIR=internal/shellembed/dist
PREFIX ?= /usr/local
INSTALL_DIR=$(PREFIX)/bin

GO=go
GOFLAGS=-ldflags="-s -w"

# Version and build info
BASE_VERSION=$(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")
COMMIT_COUNT=$(shell git rev-list --count HEAD 2>/dev/null || echo "0")
COMMIT_HASH=$(shell git rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")
VERSION?=$(BASE_VERSION)+git$(COMMIT_COUNT).$(COMMIT_HASH)
BUILD_TIME?=$(shell date -u '+%Y-%m-%d_%H:%M:%S')
COMMIT?=$(COMMIT_HASH)

BUILD_LDFLAGS=-ldflags='-s -w -X main.Version=$(VERSION) -X main.buildTime=$(BUILD_TIME) -X main.commit=$(COMMIT)'

# Architecture to build for dist target (amd64, arm64, or all)
ARCH ?= all

.PHONY: all build sync-shell dankinstall dist clean install install-all install-dankinstall uninstall uninstall-all uninstall-dankinstall install-config uninstall-config test fmt vet deps print-version help

# Default target
all: build

# Copy the quickshell UI into the embed dir (gitignored) so tagged builds
# can bake it into the binary. Dev-only files are stripped. tar -h dereferences
# the DankCommon submodule symlink; go:embed rejects symlinks. .qmlls.ini is
# excluded at copy time: it's a symlink into the quickshell runtime VFS and
# dereferencing it fails whenever the shell isn't running.
sync-shell:
	@test -e $(SHELL_SRC)/DankCommon/Widgets/DankIcon.qml || { echo "DankCommon missing: run git submodule update --init"; exit 1; }
	@rm -rf $(EMBED_DIR)
	@mkdir -p $(EMBED_DIR)
	@tar -C $(SHELL_SRC) --exclude=.qmlls.ini -chf - . | tar -C $(EMBED_DIR) -xf -
	@rm -rf $(EMBED_DIR)/scripts $(EMBED_DIR)/.claude $(EMBED_DIR)/.git* $(EMBED_DIR)/.github
	@rm -f $(EMBED_DIR)/AGENTS.md $(EMBED_DIR)/qmlformat-all.sh
	@rm -f $(EMBED_DIR)/translations/*.py $(EMBED_DIR)/translations/WORKFLOW.md
	@cd $(EMBED_DIR) && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16 > .dankrev

# Build the main binary (dms)
build: sync-shell
	@echo "Building $(BINARY_NAME)..."
	@mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 $(GO) build -tags withshell $(BUILD_LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) ./$(SOURCE_DIR)
	@echo "Build complete: $(BUILD_DIR)/$(BINARY_NAME)"

dankinstall:
	@echo "Building $(BINARY_NAME_INSTALL)..."
	@mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 $(GO) build $(BUILD_LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME_INSTALL) ./$(SOURCE_DIR_INSTALL)
	@echo "Build complete: $(BUILD_DIR)/$(BINARY_NAME_INSTALL)"

# Build distro binaries for amd64 and arm64 (Linux only, no update/greeter support)
dist: sync-shell
ifeq ($(ARCH),all)
	@echo "Building $(BINARY_NAME) for distribution (amd64 and arm64)..."
	@mkdir -p $(BUILD_DIR)
	@echo "Building for linux/amd64..."
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GO) build -tags 'distro_binary withshell' $(BUILD_LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 ./$(SOURCE_DIR)
	@echo "Building for linux/arm64..."
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 $(GO) build -tags 'distro_binary withshell' $(BUILD_LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-arm64 ./$(SOURCE_DIR)
	@echo "Distribution builds complete:"
	@echo "  $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64"
	@echo "  $(BUILD_DIR)/$(BINARY_NAME)-linux-arm64"
else
	@echo "Building $(BINARY_NAME) for distribution ($(ARCH))..."
	@mkdir -p $(BUILD_DIR)
	@echo "Building for linux/$(ARCH)..."
	CGO_ENABLED=0 GOOS=linux GOARCH=$(ARCH) $(GO) build -tags 'distro_binary withshell' $(BUILD_LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-$(ARCH) ./$(SOURCE_DIR)
	@echo "Distribution build complete:"
	@echo "  $(BUILD_DIR)/$(BINARY_NAME)-linux-$(ARCH)"
endif

build-all: build dankinstall

install:
	@echo "Installing $(BINARY_NAME) to $(INSTALL_DIR)..."
	@install -D -m 755 $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Installation complete"

install-all:
	@echo "Installing $(BINARY_NAME) to $(INSTALL_DIR)..."
	@install -D -m 755 $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Installing $(BINARY_NAME_INSTALL) to $(INSTALL_DIR)..."
	@install -D -m 755 $(BUILD_DIR)/$(BINARY_NAME_INSTALL) $(INSTALL_DIR)/$(BINARY_NAME_INSTALL)
	@echo "Installation complete"

install-dankinstall:
	@echo "Installing $(BINARY_NAME_INSTALL) to $(INSTALL_DIR)..."
	@install -D -m 755 $(BUILD_DIR)/$(BINARY_NAME_INSTALL) $(INSTALL_DIR)/$(BINARY_NAME_INSTALL)
	@echo "Installation complete"

uninstall:
	@echo "Uninstalling $(BINARY_NAME) from $(INSTALL_DIR)..."
	@rm -f $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Uninstall complete"

uninstall-all:
	@echo "Uninstalling $(BINARY_NAME) from $(INSTALL_DIR)..."
	@rm -f $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Uninstalling $(BINARY_NAME_INSTALL) from $(INSTALL_DIR)..."
	@rm -f $(INSTALL_DIR)/$(BINARY_NAME_INSTALL)
	@echo "Uninstall complete"

uninstall-dankinstall:
	@echo "Uninstalling $(BINARY_NAME_INSTALL) from $(INSTALL_DIR)..."
	@rm -f $(INSTALL_DIR)/$(BINARY_NAME_INSTALL)
	@echo "Uninstall complete"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR) $(EMBED_DIR)
	@echo "Clean complete"

test:
	@echo "Running tests..."
	$(GO) test -v ./...

fmt:
	@echo "Formatting Go code..."
	$(GO) fmt ./...

vet:
	@echo "Running go vet..."
	$(GO) vet ./...

deps:
	@echo "Updating dependencies..."
	$(GO) mod tidy
	$(GO) mod download

dev:
	@echo "Building $(BINARY_NAME) for development..."
	@mkdir -p $(BUILD_DIR)
	$(GO) build -o $(BUILD_DIR)/$(BINARY_NAME) ./$(SOURCE_DIR)
	@echo "Development build complete: $(BUILD_DIR)/$(BINARY_NAME)"

check-go:
	@echo "Checking Go version..."
	@go version | grep -E "go1\.(2[2-9]|[3-9][0-9])" > /dev/null || (echo "ERROR: Go 1.22 or higher required" && exit 1)
	@echo "Go version OK"

version: check-go
	@echo "Version: $(VERSION)"
	@echo "Build Time: $(BUILD_TIME)"
	@echo "Commit: $(COMMIT)"

print-version:
	@echo "$(VERSION)"

help:
	@echo "Available targets:"
	@echo "  all                 - Build the main binary (dms) (default)"
	@echo "  build               - Build the main binary (dms) with the embedded UI"
	@echo "  sync-shell          - Copy quickshell/ into the embed dir (runs before tagged builds)"
	@echo "  dankinstall         - Build dankinstall binary"
	@echo "  dist                - Build dms for linux amd64/arm64 (no update/greeter)"
	@echo "                        Use ARCH=amd64 or ARCH=arm64 to build only one"
	@echo "  build-all           - Build both binaries"
	@echo "  install             - Install dms to $(INSTALL_DIR)"
	@echo "  install-all         - Install both dms and dankinstall to $(INSTALL_DIR)"
	@echo "  install-dankinstall - Install only dankinstall to $(INSTALL_DIR)"
	@echo "  uninstall           - Remove dms from $(INSTALL_DIR)"
	@echo "  uninstall-all       - Remove both binaries from $(INSTALL_DIR)"
	@echo "  uninstall-dankinstall - Remove only dankinstall from $(INSTALL_DIR)"
	@echo "  clean               - Clean build artifacts"
	@echo "  test                - Run tests"
	@echo "  fmt                 - Format Go code"
	@echo "  vet                 - Run go vet"
	@echo "  deps                - Update dependencies"
	@echo "  dev                 - Build with debug info"
	@echo "  check-go            - Check Go version compatibility"
	@echo "  version             - Show version information"
	@echo "  help                - Show this help message"
